import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_ocr/core/router/app_router.dart';
import 'package:image_ocr/features/templates/providers/template_providers.dart';

import 'package:image_ocr/main.dart';
// Provider to manage the FAB menu's open/closed state.
final isFabMenuOpenProvider = StateProvider<bool>((ref) => true);

class FabMenu extends ConsumerWidget {
  final VoidCallback onTakePicture;
  final VoidCallback onShowOverlay;
  final VoidCallback onRequestRoot;
  final VoidCallback onClearCache;

  const FabMenu({
    super.key,
    required this.onTakePicture,
    required this.onShowOverlay,
    required this.onRequestRoot,
    required this.onClearCache,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isFabMenuOpen = ref.watch(isFabMenuOpenProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (isFabMenuOpen) ...[
          _FabAction(
            label: '创建模板',
            icon: const Icon(Icons.add),
            onPressed: () {
              final currentFolderId = ref.read(currentFolderIdProvider);
              ref.read(templateCreationProvider.notifier).createNew(folderId: currentFolderId);
              context.push(AppRouter.createTemplatePath);
            },
            heroTag: 'create_template_fab',
          ),
          const SizedBox(height: 12),
          _FabAction(
            label: '应用模板',
            icon: const Icon(Icons.layers_outlined),
            onPressed: () => context.push(AppRouter.applyTemplatePath),
            heroTag: 'apply_template_fab',
          ),
          const SizedBox(height: 12),
          _FabAction(
            label: '拍照',
            icon: const Icon(Icons.camera_alt_outlined),
            onPressed: onTakePicture,
            heroTag: 'take_picture_fab',
          ),
          const SizedBox(height: 12),
          _FabAction(
            label: '截屏悬浮窗',
            icon: const Icon(Icons.screenshot_monitor),
            onPressed: onShowOverlay,
            heroTag: 'screenshot_fab',
          ),
          const SizedBox(height: 12),
          // --- [NEW] Root Permission FAB Action ---
          Consumer(
            builder: (context, ref, child) {
              final isRootGranted = ref.watch(isRootGrantedProvider);
              return _FabAction(
                label: isRootGranted ? 'Root 模式已激活' : '请求 Root 权限',
                icon: Icon(
                  isRootGranted ? Icons.check_circle : Icons.security,
                  color: isRootGranted ? Colors.green : null,
                ),
                onPressed: isRootGranted ? () {} : onRequestRoot,
                heroTag: 'root_fab',
              );
            },
          ),
          const SizedBox(height: 12),
          _FabAction(
            label: '清空缓存文件夹',
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: onClearCache,
            heroTag: 'clear_cache_fab',
          ),
          const SizedBox(height: 20),
        ],
        FloatingActionButton(
          heroTag: 'main_fab',
          child: Icon(isFabMenuOpen ? Icons.close : Icons.menu),
          onPressed: () {
            ref.read(isFabMenuOpenProvider.notifier).update((state) => !state);
          },
        ),
      ],
    );
  }
}

class _FabAction extends ConsumerWidget {
  final String label;
  final Widget icon;
  final VoidCallback onPressed;
  final String heroTag;

  const _FabAction({
    required this.label,
    required this.icon,
    required this.onPressed,
    required this.heroTag,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Card(
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
            child: Text(label),
          ),
        ),
        const SizedBox(width: 16),
        FloatingActionButton(
          heroTag: heroTag,
          onPressed: () {
            onPressed();
            // Close the menu after an action is tapped.
            ref.read(isFabMenuOpenProvider.notifier).state = false;
          },
          child: icon,
        ),
      ],
    );
  }
}