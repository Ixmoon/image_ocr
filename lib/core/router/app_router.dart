import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_clone_tool/features/home/screens/home_screen.dart';
import 'package:image_clone_tool/features/processing/screens/batch_preview_screen.dart';
import 'package:image_clone_tool/features/processing/screens/preview_screen.dart';
import 'package:image_clone_tool/features/templates/models/template.dart';
import 'package:image_clone_tool/features/templates/screens/apply_template_screen.dart';
import 'package:image_clone_tool/features/templates/screens/create_template_screen.dart';
import 'package:image_clone_tool/features/templates/screens/define_field_screen.dart';
import 'package:image_clone_tool/features/templates/models/template_field.dart';

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
  static const String defineFieldPath = '/define-field';
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
      path: defineFieldPath,
      builder: (context, state) {
        // 接收从 context.push 传递过来的 extra 参数
        final fieldToEdit = state.extra as TemplateField?;
        return DefineFieldScreen(fieldToEdit: fieldToEdit);
      },
    ),
    GoRoute(
      path: applyTemplatePath,
      builder: (context, state) => ApplyTemplateScreen(
        template: state.extra as Template,
      ),
    ),
    GoRoute(
      path: previewPath,
      builder: (context, state) => PreviewScreen(
        imagePath: state.extra as String,
      ),
    ),
    GoRoute(
      path: batchPreviewPath,
      builder: (context, state) => BatchPreviewScreen(
        resultImagePaths: state.extra as List<String>,
      ),
    ),
  ];
}