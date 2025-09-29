import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:isolate';
import 'dart:ui';
import 'package:image_ocr/features/overlay/overlay_widget.dart';
import 'package:image_ocr/features/processing/providers/image_processing_provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:image_ocr/core/router/app_router.dart';
import 'package:image_ocr/core/theme/app_theme.dart';
import 'package:image_ocr/core/utils/hive_type_adapters.dart' as custom_adapters;
import 'package:image_ocr/features/processing/services/processing_isolate_pool_service.dart';
import 'package:image_ocr/features/templates/models/folder.dart';
import 'package:image_ocr/features/templates/models/template.dart';
import 'package:image_ocr/features/templates/models/template_field.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

// --- Isolate Communication ---
final ReceivePort _port = ReceivePort();
const String _kPortName = "main_isolate";

Future<void> main() async {
  // 确保Flutter绑定已初始化
  WidgetsFlutterBinding.ensureInitialized();

  // --- Isolate Communication Setup ---
  if (IsolateNameServer.lookupPortByName(_kPortName) != null) {
    IsolateNameServer.removePortNameMapping(_kPortName);
  }
  IsolateNameServer.registerPortWithName(_port.sendPort, _kPortName);

  // 初始化Hive
  await Hive.initFlutter();
  Hive.registerAdapter(FolderAdapter());
  Hive.registerAdapter(TemplateAdapter());
  Hive.registerAdapter(TemplateFieldAdapter());
  Hive.registerAdapter(custom_adapters.RectAdapter());

  // 打开所有需要的 Box
  await Hive.openBox<Folder>('folders');
  await Hive.openBox<Template>('templates');
  await Hive.openBox<TemplateField>('template_fields');

  final container = ProviderContainer();
  final pool = container.read(processingIsolatePoolProvider);
  
  // 后台预热
  pool.warmUpAsync();

  // --- [添加] 程序启动时清理缓存图片 ---
  await _clearSavedImages();

  // 监听来自悬浮窗的消息
  _port.listen((message) {
    debugPrint('[主应用] 收到悬浮窗消息: $message');
    
    // 假设消息格式为 [String command, dynamic data]
    if (message is List && message.length == 2) {
      final command = message[0] as String;
      final data = message[1];
      
      if (command == 'process_screenshot') {
        final imagePath = data['imagePath'] as String;
        final templateId = data['templateId'] as String;
        
        // 在主 Isolate 中查找模板
        final templatesBox = Hive.box<Template>('templates');
        final matchingTemplates = templatesBox.values.where((t) => t.id == templateId);
        
        if (matchingTemplates.isNotEmpty) {
          final template = matchingTemplates.first;
          // 使用 container 来访问 provider
          container.read(imageProcessingProvider.notifier).processBatch(
            templates: [template],
            targetImagePaths: [imagePath],
          );
          debugPrint('[主应用] 开始处理截屏图片: $imagePath');
        } else {
          debugPrint('[主应用] 未找到模板: $templateId');
        }
      } else if (command == 'request_screenshot_processing') {
        final templateId = data['templateId'] as String;
        final templateName = data['templateName'] as String?;
        
        debugPrint('[主应用] 收到截屏处理请求: 模板=$templateName, ID=$templateId');
        
        // 发送确认消息回悬浮窗
        final overlayPort = IsolateNameServer.lookupPortByName('OVERLAY');
        overlayPort?.send('截屏请求已接收，模板: $templateName');
        
        // 这里可以添加自动截屏或打开图库的逻辑
        // 暂时只是确认收到请求
      }
    }
  });

  // 运行应用
  runApp(
    ProviderScope(
      child: const MyApp(),
    ),
  );
}

// --- Overlay Window Entry Point ---
@pragma("vm:entry-point")
void overlayMain() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化 Hive (悬浮窗需要访问模板数据)
  await Hive.initFlutter();
  Hive.registerAdapter(FolderAdapter());
  Hive.registerAdapter(TemplateAdapter());
  Hive.registerAdapter(TemplateFieldAdapter());
  Hive.registerAdapter(custom_adapters.RectAdapter());

  // 打开需要的 Box
  await Hive.openBox<Folder>('folders');
  await Hive.openBox<Template>('templates');
  await Hive.openBox<TemplateField>('template_fields');
  
  runApp(
    const ProviderScope(
      child: OverlayWidget(),
    ),
  );
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 从路由配置中获取GoRouter实例
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: '图像置换',
      
      // 应用主题配置
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system, // 自动跟随系统设置切换深浅色模式

      // GoRouter的路由配置
      routerConfig: router,

      debugShowCheckedModeBanner: false,
    );
  }
}

/// 清理应用在公共相册中创建的图片文件夹
Future<void> _clearSavedImages() async {
  debugPrint('[启动清理] 开始尝试清理已保存的图片目录...');
  try {
    // 在执行任何文件操作前，首先请求权限
    final status = await Permission.manageExternalStorage.request();
    if (status.isGranted) {
      debugPrint('[启动清理] 存储权限已授予。');
      final externalDir = await getExternalStorageDirectory();
      if (externalDir != null) {
        // 从应用私有目录路径中解析出外部存储的根路径 (e.g., /storage/emulated/0)
        // 这是一个适配方案，因为 path_provider 没有直接提供公共目录的根路径
        final rootPath = externalDir.path.split('/Android').first;
        final saveDir = Directory('$rootPath/Pictures/ImageOCR');
        
        debugPrint('[启动清理] 目标目录: ${saveDir.path}');
        if (await saveDir.exists()) {
          debugPrint('[启动清理] 目录存在，正在删除...');
          await saveDir.delete(recursive: true);
          debugPrint('[启动清理] 目录已成功删除。');
          // 重新创建目录以便后续保存操作
          await saveDir.create(recursive: true);
          debugPrint('[启动清理] 已重新创建空目录。');
        } else {
          debugPrint('[启动清理] 目录不存在，无需清理。');
        }
      } else {
        debugPrint('[启动清理] 无法获取外部存储目录。');
      }
    } else {
      debugPrint('[启动清理] 未授予存储权限，跳过清理操作。');
    }
  } catch (e) {
    debugPrint('[启动清理] 清理已保存图片目录时发生错误: $e');
  }
}