import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:image_ocr/core/constants/app_constants.dart';
import 'package:image_ocr/core/services/notification_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:gal/gal.dart';

// --- Isolate Communication ---
final ReceivePort _port = ReceivePort();
const String _kPortNameHome = "UI";

// --- Platform Channels ---
const EventChannel _screenshotEventChannel = EventChannel('com.lxmoon.image_ocr/screenshot_events');
const MethodChannel _screenshotMethodChannel = MethodChannel('com.lxmoon.image_ocr/screenshot');

// 用于在 main isolate 中存储待处理的模板列表
final templatesForProcessingProvider = StateProvider<List<Template>>((ref) => []);
// 用于触发 UI 层的截屏请求
final screenshotRequestedProvider = StateProvider<bool>((ref) => false);

// --- [NEW] Provider to hold the state of the overlay for restoration ---
class OverlayState {
  final bool isExpanded;
  OverlayState({this.isExpanded = false});
}
final overlayStateToRestoreProvider = StateProvider<OverlayState>((ref) => OverlayState());


// --- [NEW] 应用生命周期状态管理 ---
final appLifecycleStateProvider = StateProvider<AppLifecycleState>((ref) => AppLifecycleState.resumed);

// --- [NEW] 后台截屏结果缓存 ---
class PendingScreenshotResult {
  final String? path;
  final String? error;
  final DateTime timestamp;
  
  PendingScreenshotResult({this.path, this.error, required this.timestamp});
}
final pendingScreenshotResultProvider = StateProvider<PendingScreenshotResult?>((ref) => null);

// --- [NEW] Root权限状态管理 ---
final isRootGrantedProvider = StateProvider<bool>((ref) => false);

Future<void> main() async {
  // 1. 确保Flutter绑定已初始化
  WidgetsFlutterBinding.ensureInitialized();

  // 2. 将非关键的清理任务移至后台执行，不阻塞启动
  // Defer non-critical cleanup until after the first frame to improve startup time.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    _clearSavedImages();
  });

  // 3. 并行初始化核心服务 (通知、数据库等)
  await Future.wait([
    NotificationService().initialize(),
    _initHive(),
  ]);
  
  // 4. 设置 Isolate 通信和事件监听
  final container = ProviderContainer();
  _setupIsolateCommunication(container);
  _setupScreenshotListener(container);
  _setupAppLifecycleListener(container);

  // 5. 异步预热 Isolate 池，不阻塞启动
  container.read(processingIsolatePoolProvider).warmUpAsync();

  // 6. 运行应用
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const MyApp(),
    ),
  );
}

/// 初始化 Hive 数据库
Future<void> _initHive() async {
  await Hive.initFlutter();
  Hive.registerAdapter(FolderAdapter());
  Hive.registerAdapter(TemplateAdapter());
  Hive.registerAdapter(TemplateFieldAdapter());
  Hive.registerAdapter(custom_adapters.RectAdapter());

  // 并行打开所有需要的 Box
  await Future.wait([
    Hive.openBox<Folder>('folders'),
    Hive.openBox<Template>('templates'),
    Hive.openBox<TemplateField>('template_fields'),
  ]);
}

/// 设置 Isolate 之间的通信
void _setupIsolateCommunication(ProviderContainer container) {
  if (IsolateNameServer.lookupPortByName(_kPortNameHome) != null) {
    IsolateNameServer.removePortNameMapping(_kPortNameHome);
  }
  IsolateNameServer.registerPortWithName(_port.sendPort, _kPortNameHome);

  _port.listen((message) {
    if (message is Map<String, dynamic>) {
      final command = message['command'] as String?;
      final payload = message['payload'] as Map<dynamic, dynamic>? ?? {};
      final wasExpanded = payload['wasExpanded'] as bool? ?? false;

      // Store the overlay's state for later restoration.
      container.read(overlayStateToRestoreProvider.notifier).state = OverlayState(isExpanded: wasExpanded);

      if (command == 'request_screenshot_and_process' || command == 'request_screenshot_only') {
        if (command == 'request_screenshot_and_process') {
          final templateList = (payload['templates'] as List? ?? []).cast<Map<dynamic, dynamic>>();
          final templatesBox = Hive.box<Template>('templates');
          final templateIds = templateList.map((t) => t['templateId'] as String);
          final matchingTemplates = templateIds
              .map((id) => templatesBox.get(id))
              .where((template) => template != null)
              .cast<Template>()
              .toList();
          container.read(templatesForProcessingProvider.notifier).state = matchingTemplates;
        } else {
          container.read(templatesForProcessingProvider.notifier).state = [];
        }
        
        // Directly trigger the screenshot from here.
        _screenshotMethodChannel.invokeMethod('takeScreenshot');
      } else if (command == 'trigger_screenshot_direct') {
        // 悬浮窗直接触发截屏的请求
        _screenshotMethodChannel.invokeMethod('takeScreenshot');
      }
    }
  });
}

/// 设置应用生命周期监听器
void _setupAppLifecycleListener(ProviderContainer container) {
  WidgetsBinding.instance.addObserver(_AppLifecycleObserver(container));
}

/// 应用生命周期观察者
class _AppLifecycleObserver extends WidgetsBindingObserver {
  final ProviderContainer container;
  
  _AppLifecycleObserver(this.container);
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    container.read(appLifecycleStateProvider.notifier).state = state;
    
    // 当应用从后台恢复到前台时，检查是否有待处理的截屏结果
    if (state == AppLifecycleState.resumed) {
      _handlePendingScreenshotResult(container);
    }
  }
}

/// 处理后台缓存的截屏结果
void _handlePendingScreenshotResult(ProviderContainer container) {
  final pendingResult = container.read(pendingScreenshotResultProvider);
  if (pendingResult != null) {
    // 清除缓存
    container.read(pendingScreenshotResultProvider.notifier).state = null;
    
    // 处理结果
    if (pendingResult.path != null) {
      _handleScreenshotSuccess(container, pendingResult.path!);
    } else if (pendingResult.error != null) {
      _handleScreenshotError(container, pendingResult.error!);
    }
  }
}

/// 设置原生截图事件的监听器（最终版）
void _setupScreenshotListener(ProviderContainer container) {
  _screenshotEventChannel.receiveBroadcastStream().listen((event) async {
    try {
      if (event is Map) {
        final type = event['type'] as String?;
        if (type == 'success') {
          final path = event['path'] as String?;
          if (path != null) {
            await _handleScreenshotSuccess(container, path);
          } else {
            await _handleScreenshotError(container, 'Screenshot path was null.');
          }
        }
      } else {
         // 处理非Map类型的事件，例如错误字符串
         final errorMsg = event.toString();
         await _handleScreenshotError(container, errorMsg);
      }
    } catch (e) {
      final errorMsg = e is PlatformException ? e.message ?? '未知平台错误' : e.toString();
      await _handleScreenshotError(container, errorMsg);
    }
  }, onError: (error) async {
      // 明确处理来自 stream 的错误
      final errorMsg = error is PlatformException ? error.message ?? '未知平台错误' : error.toString();
      await _handleScreenshotError(container, errorMsg);
  });
}

/// 处理截屏成功的情况 (V2: 移���生命周期检查，总是立即处理)
Future<void> _handleScreenshotSuccess(ProviderContainer container, String path) async {
  // 无论应用在前台还是后台，都立即开始处理
  final templatesToProcess = container.read(templatesForProcessingProvider);

  if (templatesToProcess.isNotEmpty) {
    // 有模板，进入处理流程
    await _handleProcessing(container, path, templatesToProcess);
  } else {
    // 没有模板，仅保存截图
    await _handleScreenshotOnly(path);
  }
  
  // 通知悬浮窗处理完成
  _notifyOverlayScreenshotDone(container);
  
  // 重置状态，为下一次截屏做准备
  container.read(templatesForProcessingProvider.notifier).state = [];
}

/// 处理截屏错误的情况 (V2: 移除生命周期检查)
Future<void> _handleScreenshotError(ProviderContainer container, String errorMsg) async {
  // 无论应用状态如何，都直接显示错误通知
  await NotificationService().showNotification(title: '处理失败', body: errorMsg);
  
  // 通知��浮窗处理完成（即使是失败了）
  _notifyOverlayScreenshotDone(container);
  
  // 重置状态
  container.read(templatesForProcessingProvider.notifier).state = [];
}

void _notifyOverlayScreenshotDone(ProviderContainer container) {
  final overlayPort = IsolateNameServer.lookupPortByName('OVERLAY');
  final overlayState = container.read(overlayStateToRestoreProvider);
  overlayPort?.send({
    'command': 'screenshot_done',
    'wasExpanded': overlayState.isExpanded,
  });
}

/// 处理带模板的截图流程 (V4: 保存处理后的图片到相册)
Future<void> _handleProcessing(ProviderContainer container, String path, List<Template> templates) async {
  final imageProcessor = container.read(imageProcessingProvider.notifier);
  
  final finalState = await imageProcessor.processBatch(
    templates: templates,
    targetImagePaths: [path],
  );
  
  final successCount = finalState.results.length;

  if (successCount > 0) {
    try {
      // 优化：直接使用处理后的字节数据，避免临时文件
      for (final originalPath in finalState.results) {
        final processedImageData = imageProcessor.getProcessedImageData(originalPath);
        if (processedImageData != null) {
          // 创建一个临时文件用于 Gal.putImage（因为它需要文件路径）
          final tempDir = Directory.systemTemp;
          final tempFileName = 'final_${DateTime.now().millisecondsSinceEpoch}.png';
          final tempFile = File('${tempDir.path}/$tempFileName');
          
          await tempFile.writeAsBytes(processedImageData);
          
          // 使用 Gal 保存处理后的图片到指定相册
          await Gal.putImage(tempFile.path, album: AppConstants.imageAlbumName);
          
          // 立即清理临时文件和内存数据
          try {
            await tempFile.delete();
            imageProcessor.clearProcessedImageData(originalPath);
          } catch (e) {
            debugPrint("Failed to cleanup temporary data: $e");
          }
        }
      }
      
      // 删除原始截图（已被处理后的图片替换）
      try {
        final originalFile = File(path);
        if (await originalFile.exists()) {
          await originalFile.delete();
        }
      } catch (e) {
        debugPrint("Failed to delete original screenshot after successful processing: $e");
      }

      await NotificationService().showNotification(
        title: '处理完成',
        body: '成功应用 ${successCount} 个模板，图片已保存至 ${AppConstants.imageAlbumName}'
      );
    } catch (e) {
      // 如果保存失败，清理数据并删除原图
      for (final originalPath in finalState.results) {
        imageProcessor.clearProcessedImageData(originalPath);
      }
      
      try {
        final originalFile = File(path);
        if (await originalFile.exists()) {
          await originalFile.delete();
        }
      } catch (deleteError) {
        debugPrint("Failed to delete original screenshot after save failure: $deleteError");
      }
      
      await NotificationService().showNotification(
        title: '保存失败',
        body: '处理成功但保存到相册失败: $e，原图已删除'
      );
    }
  } else {
    // --- 核心修复：处理失败时，删除原始截图 ---
    try {
      final originalFile = File(path);
      if (await originalFile.exists()) {
        await originalFile.delete();
      }
    } catch (e) {
      // 文件删除失败是一个小问题，不应阻塞主流程，记录日志即可
      debugPrint("Failed to delete original screenshot after processing failure: $e");
    }

    String error = finalState.error ?? '未知错误';
    if (error.contains('No anchors were found')) {
      error = '图片中未找到模板所需的锚点，截图已删除';
    } else {
      error = '模板应用失败，截图已删除';
    }
    await NotificationService().showNotification(title: '处理失败', body: error);
  }
}

/// 处理仅截图的流程 (V2: 移除重复保存)
Future<void> _handleScreenshotOnly(String path) async {
  // 原生层已经完成了物理保存和通知媒体库。
  // Flutter层在这里只需要发送一个最终的、明确的成功通知。
  final savedFile = File(path);
  if (await savedFile.exists()) {
    await NotificationService().showNotification(
        title: '截图已保存',
        body: '图片已保存至相册的 ${AppConstants.imageAlbumName} 文件夹'
    );
  } else {
    const errorMsg = '截图文件在处理过程中丢失';
    await NotificationService().showNotification(title: '保存失败', body: errorMsg);
  }
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
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: '图像置换',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}

/// 清理应用在公共相册中创建的图片文件夹
Future<void> _clearSavedImages() async {
  try {
    // 首先检查权限状态
    var status = await Permission.manageExternalStorage.status;

    // 如果权限未被授予，则请求它。这将引导用户到系统设置页面。
    if (!status.isGranted) {
      status = await Permission.manageExternalStorage.request();
    }

    // 在用户从设置页面返回后，如果权限已授予，则执行清理操作
    if (status.isGranted) {
      // Get the directory path from the native side to ensure consistency
      final String? dirPath = await _screenshotMethodChannel.invokeMethod('getPicturesDirectory');
      if (dirPath != null) {
        final saveDir = Directory(dirPath);
        if (await saveDir.exists()) {
          await saveDir.delete(recursive: true);
        }
        // Always ensure the directory exists
        await saveDir.create(recursive: true);
      }
    }
  } catch (e) {
    // 记录错误，但不应让它使应用崩溃
    debugPrint("Error in _clearSavedImages: $e");
  }
}