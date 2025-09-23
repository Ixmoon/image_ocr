import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:image_ocr/core/router/app_router.dart';
import 'package:image_ocr/core/theme/app_theme.dart';
import 'package:image_ocr/core/utils/hive_type_adapters.dart' as custom_adapters;
import 'package:image_ocr/features/templates/models/folder.dart';
import 'package:image_ocr/features/templates/models/template.dart';
import 'package:image_ocr/features/templates/models/template_field.dart';

Future<void> main() async {
  // 确保Flutter绑定已初始化，这是调用原生代码前所必需的
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化Hive，用于本地持久化存储
  await Hive.initFlutter();

  // 注册自定义的Adapter，以便Hive能够序列化和反序列化我们的数据模型
  // 注意：这些Adapter是在template.g.dart和template_field.g.dart中定义的
  Hive.registerAdapter(FolderAdapter());
  Hive.registerAdapter(TemplateAdapter());
  Hive.registerAdapter(TemplateFieldAdapter());
  Hive.registerAdapter(custom_adapters.RectAdapter());

  // --- [添加] 打开所有需要的 Box ---
  await Hive.openBox<Folder>('folders');
  await Hive.openBox<Template>('templates');
  await Hive.openBox<TemplateField>('template_fields'); // 为 TemplateField 创建并打开一个新 Box

  // 运行应用
  runApp(
    // ProviderScope是Riverpod的根Widget，用于存储所有Provider的状态
    const ProviderScope(
      child: MyApp(),
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