import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_ocr/features/home/screens/home_screen.dart';
import 'package:image_ocr/features/processing/screens/batch_preview_screen.dart';
import 'package:image_ocr/features/processing/screens/preview_screen.dart';
import 'package:image_ocr/features/templates/models/template.dart';
import 'package:image_ocr/features/templates/screens/apply_template_screen.dart';
import 'package:image_ocr/features/templates/screens/create_template_screen.dart';
import 'package:image_ocr/features/processing/models/image_processing_state.dart';

// 将GoRouter实例放入Provider中，便于管理和测试
final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: AppRouter.homePath,
    routes: AppRouter.routes,
  );
});

// 应用路由配置类
class AppRouter {
  AppRouter._();

  // 路由路径常量，方便统一管理和引用
  static const String homePath = '/';
  static const String createTemplatePath = '/create-template';
  static const String applyTemplatePath = '/apply-template';
  static const String previewPath = '/preview';
  static const String batchPreviewPath = '/batch-preview';

  // 路由列表
  static final List<GoRoute> routes = [
    GoRoute(
      path: homePath,
      builder: (context, state) => const HomeScreen(),
    ),
    GoRoute(
      path: createTemplatePath,
      builder: (context, state) => const CreateTemplateScreen(),
      routes: [
        GoRoute(
          path: ':templateId',
          builder: (context, state) => CreateTemplateScreen(
            templateId: state.pathParameters['templateId'],
          ),
        ),
      ]
    ),
    GoRoute(
      path: applyTemplatePath,
      builder: (context, state) => ApplyTemplateScreen(
        initialTemplate: state.extra as Template?,
      ),
    ),
    GoRoute(
      path: previewPath,
      builder: (context, state) {
        if (state.extra is String) {
          return PreviewScreen(imagePath: state.extra as String);
        }
        if (state.extra is Map<String, dynamic>) {
          final args = state.extra as Map<String, dynamic>;
          return PreviewScreen(
            imagePath: args['imagePath'] as String,
            canReplace: args['canReplace'] as bool? ?? false,
          );
        }
        // Fallback or error case
        return const Scaffold(body: Center(child: Text('无效的预览参数')));
      },
    ),
    GoRoute(
      path: batchPreviewPath,
      builder: (context, state) => BatchPreviewScreen(
        processingState: state.extra as ImageProcessingState,
      ),
    ),
  ];
}