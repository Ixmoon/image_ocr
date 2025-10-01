// --- Drag-and-Drop Highlighting Implementation Notes (FINAL - Robust Version) ---
//
// PROBLEM:
// The `drag_and_drop_lists` plugin has fundamental conflicts that cause crashes
// when its list items are wrapped with complex widgets like `GlobalKey`, `KeyedSubtree`,
// or even stateful widgets that report their layout. All previous attempts failed
// because they tried to solve the problem *within* the list item.
//
// FINAL SOLUTION (Overlay Architecture):
// We completely separate the drag-and-drop targets from the list items by using a
// transparent overlay. This is the definitive pattern for this kind of problem.
//
// 1. Stack Layout:
//    - The `DragAndDropLists` widget is placed inside a `Stack`.
//    - On top of it, we place a transparent `_DragTargetOverlay` widget.
//
// 2. Position Registry (`folderRectsProvider`):
//    - The `_FolderListItem` is converted back to a `StatefulWidget`. Its only job
//      is to report its screen position (`Rect`) to the `folderRectsProvider`
//      whenever it's built or laid out. It holds no keys.
//
// 3. Dynamic Targets in the Overlay:
//    - The `_DragTargetOverlay` listens to the `folderRectsProvider`.
//    - For each `Rect` in the provider, the overlay builds a corresponding,
//      perfectly positioned `DragTarget` widget.
//    - These targets are completely independent of the list below. They handle
//      hover detection (highlighting) and accepting drops.
//
// 4. Clean Separation of Concerns:
//    - `drag_and_drop_lists`: Only handles reordering and displaying the list.
//    - `_FolderListItem`: Only displays folder UI and reports its position.
//    - `_DragTargetOverlay`: Only handles drop logic and highlighting.
//
// This architecture eliminates all gesture and build-context conflicts, providing
// a stable and reliable solution.
//
import 'package:drag_and_drop_lists/drag_and_drop_lists.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_ocr/core/router/app_router.dart';
import 'package:image_ocr/features/templates/models/folder.dart';
import 'package:image_ocr/features/templates/models/template.dart';
import 'package:image_ocr/features/templates/providers/template_providers.dart';
import 'package:flutter/services.dart';
import 'package:image_ocr/core/constants/app_constants.dart';
import 'dart:ui';
import 'package:image_ocr/main.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:gal/gal.dart';
import 'package:image_ocr/features/home/widgets/fab_menu.dart';


final hoveredFolderIdProvider = StateProvider<String?>((ref) => null);
final isDraggingProvider = StateProvider<bool>((ref) => false);
final draggedItemProvider = StateProvider<DragAndDropItem?>((ref) => null);
final folderRectsProvider = StateProvider<Map<String, Rect>>((ref) => {});

// --- Main Screen Widget ---

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final ImagePicker _picker = ImagePicker();
  final Map<String, GlobalKey> _folderKeys = {};
  
  @override
  void initState() {
    super.initState();
  }

  Future<void> _takePicture() async {
    // 1. 检查和请求相机��限
    final cameraStatus = await Permission.camera.request();
    if (!cameraStatus.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('需要相机权限才能拍照')),
        );
      }
      return;
    }

    // 2. 检查和请求存储权限 (虽然主要用于保存，但最好也检查一下)
    final storageStatus = await Permission.manageExternalStorage.request();
     if (!storageStatus.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('需要文件访问权限才能保存照片')),
        );
      }
      return;
    }

    try {
      // 3. 调用相机
      final XFile? photo = await _picker.pickImage(source: ImageSource.camera);
      if (photo == null) {
        return;
      }

      // 4. 直接使用 Gal 保存图片到指定相册
      await Gal.putImage(photo.path, album: AppConstants.imageAlbumName);
      
      // 5. 用户反馈
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('照片已保存至 ${AppConstants.imageAlbumName}')),
        );
      }

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('保存照片失败: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _showOverlay() async {
    // This button now also uses the main screenshot flow.
    // The overlay itself will be simplified to just trigger the Riverpod state.
    await _triggerScreenshotFlow(showOverlay: true);
  }

  Future<void> _triggerScreenshotFlow({bool showOverlay = false}) async {
    const MethodChannel screenshotChannel = MethodChannel('com.lxmoon.image_ocr/screenshot');
    try {
      // 1. Check for Accessibility permission
      final bool isGranted = await screenshotChannel.invokeMethod('checkAccessibilityPermission');

      if (!isGranted) {
        if (mounted) {
          await showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('需要无障碍服务权限'),
              content: const Text('为了在任何界面都能响应截屏，需要您在系统设置中开启本应用的无障碍服务。'),
              actions: [
                TextButton(
                  child: const Text('取消'),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                FilledButton(
                  child: const Text('去开启'),
                  onPressed: () {
                    screenshotChannel.invokeMethod('requestAccessibilityPermission');
                    Navigator.of(context).pop();
                  },
                ),
              ],
            ),
          );
        }
        return; // Stop the flow if permission is not granted.
      }

      // 2. If permission is granted, decide whether to show overlay or take screenshot directly
      if (showOverlay) {
        // --- [FIX] Ensure overlay permission is granted before showing ---
        final hasPermission = await FlutterOverlayWindow.isPermissionGranted();
        if (!hasPermission) {
          final granted = await FlutterOverlayWindow.requestPermission();
          // --- [FIX] Handle nullable boolean. `granted != true` covers both false and null. ---
          if (granted != true) {
            return;
          }
        }

        if (!await FlutterOverlayWindow.isActive()) {
          // --- [ULTIMATE FIX] Use a context-independent method to get DPR ---
          // This avoids issues where the widget's context might be stale when called from a listener.
          final overlayState = ref.read(overlayStateToRestoreProvider);
          final dpr = PlatformDispatcher.instance.views.first.devicePixelRatio;

          final logicalWidth = overlayState.isExpanded ? 350 : 60;
          final logicalHeight = overlayState.isExpanded ? 600 : 60;

          final physicalWidth = (logicalWidth * dpr).round();
          final physicalHeight = (logicalHeight * dpr).round();

          await FlutterOverlayWindow.showOverlay(
            enableDrag: true,
            overlayTitle: "截屏悬浮窗",
            overlayContent: '正在运行...',
            flag: OverlayFlag.defaultFlag,
            visibility: NotificationVisibility.visibilityPublic,
            height: physicalHeight,
            width: physicalWidth,
            startPosition: const OverlayPosition(0, 0),
          );
        }
      } else {
        // This branch is not used in the current overlay-first workflow.
        // It's kept for potential future features like a 'quick screenshot' button
        // directly within the app, but the SnackBar is removed to avoid confusion.
        await screenshotChannel.invokeMethod('takeScreenshot');
      }

    } on PlatformException catch (e) {
      final errorMessage = e.message ?? '未知原生错误';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('操作失败: $errorMessage')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('发生未知错误: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // --- Screenshot Request Listener ---
    ref.listen<bool>(screenshotRequestedProvider, (previous, next) {
      if (next == true) {
        ref.read(screenshotRequestedProvider.notifier).state = false;
        _triggerScreenshotFlow();
      }
    });

    final navigationStack = ref.watch(folderNavigationStackProvider);
    final currentFolderId = navigationStack.last;
    final contentsAsyncValue = ref.watch(folderContentsProvider(currentFolderId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('我的模板'),
        leading: navigationStack.length > 1
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => ref.read(folderNavigationStackProvider.notifier).pop(),
              )
            : null,
        actions: [
          IconButton(
            icon: const Icon(Icons.create_new_folder_outlined),
            tooltip: '新建文件夹',
            onPressed: () => _showCreateFolderDialog(context, ref),
          ),
        ],
      ),
      body: contentsAsyncValue.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('加载失败: $err')),
        data: (contents) {
          if (contents.isEmpty && navigationStack.length <= 1) {
            return const _EmptyState();
          }
          
          // --- Performance Optimization ---
          // Instead of having each list item report its own bounds on every build,
          // we now manage GlobalKeys here and calculate all bounds at once, only
          // when a drag operation begins. This significantly reduces build-time
          // overhead and widget rebuilds.
          final onScreenFolderIds = contents.whereType<Folder>().map((f) => f.id).toSet();
          _folderKeys.removeWhere((id, key) => !onScreenFolderIds.contains(id));
          for (final folder in contents.whereType<Folder>()) {
            _folderKeys.putIfAbsent(folder.id, () => GlobalKey());
          }

          final contentItems = contents.map((item) {
            final childWidget = item is Folder
                ? _FolderListItem(folder: item, key: _folderKeys[item.id]!)
                : _TemplateListItem(template: item as Template);
            return DragAndDropItem(child: childWidget);
          }).toList();

          final contentList = DragAndDropList(
            children: contentItems,
          );

          return Column(
            children: [
              if (navigationStack.length > 1)
                _DragToParentNavBar(currentFolderId: currentFolderId),
              Expanded(
                child: Stack(
                  clipBehavior: Clip.none, // Allow targets to receive events outside the Stack's bounds.
                  children: [
                    DragAndDropLists(
                      children: [contentList],
                      onItemReorder: (int oldItemIndex, int oldListIndex, int newItemIndex, int newListIndex) {
                        ref.read(templatesAndFoldersActionsProvider).reorderChildren(currentFolderId, oldItemIndex, newItemIndex);
                      },
                      onListReorder: (int oldListIndex, int newListIndex) {
                        // Not used
                      },
                      onItemDraggingChanged: (item, isDragging) {
                        ref.read(isDraggingProvider.notifier).state = isDragging;
                        if (isDragging) {
                          ref.read(draggedItemProvider.notifier).state = item;
                          
                          // --- Performance Optimization: Calculate all rects on drag start ---
                          final newRects = <String, Rect>{};
                          _folderKeys.forEach((folderId, key) {
                            final renderBox = key.currentContext?.findRenderObject() as RenderBox?;
                            if (renderBox != null && renderBox.hasSize) {
                              final rect = renderBox.localToGlobal(Offset.zero) & renderBox.size;
                              newRects[folderId] = rect;
                            }
                          });
                          ref.read(folderRectsProvider.notifier).state = newRects;

                        } else {
                          ref.read(hoveredFolderIdProvider.notifier).state = null;
                          ref.read(draggedItemProvider.notifier).state = null;
                          // Clear rects when drag ends to free up memory and prevent stale data.
                          ref.read(folderRectsProvider.notifier).state = {};
                        }
                      },
                      // This callback is no longer used for dropping on folders.
                      itemOnAccept: (DragAndDropItem incoming, DragAndDropItem target) {},
                      listPadding: const EdgeInsets.all(8.0),
                      itemDecorationWhileDragging: BoxDecoration(
                        color: Theme.of(context).cardColor,
                        boxShadow: [BoxShadow(color: Colors.black.withAlpha((255 * 0.2).round()), blurRadius: 4)],
                      ),
                      listDragHandle: const DragHandle(
                        verticalAlignment: DragHandleVerticalAlignment.top,
                        child: SizedBox.shrink(),
                      ),
                    ),
                    // The transparent overlay for handling drop targets.
                    const _DragTargetOverlay(),
                  ],
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FabMenu(
        onTakePicture: _takePicture,
        onShowOverlay: _showOverlay,
      ),
    );
  }

}

// --- Overlay for Drop Targets ---

class _DragTargetOverlay extends ConsumerWidget {
  const _DragTargetOverlay();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDragging = ref.watch(isDraggingProvider);
    if (!isDragging) {
      return const SizedBox.shrink();
    }

    final folderRects = ref.watch(folderRectsProvider);
    final currentFolderId = ref.watch(currentFolderIdProvider);
    final overlayBox = context.findRenderObject() as RenderBox?;

    // If the overlay isn't laid out yet or has no size, don't build targets
    // to prevent incorrect coordinate conversions during the first frames of a drag.
    if (overlayBox == null || !overlayBox.hasSize) {
      return const SizedBox.shrink();
    }

    return Stack(
      clipBehavior: Clip.none, // This is the crucial fix for the nested clipping issue.
      children: folderRects.entries.map((entry) {
        final folderId = entry.key;
        final globalRect = entry.value;

        // Convert the folder's global screen Rect to a local Rect relative to this Stack.
        final localTopLeft = overlayBox.globalToLocal(globalRect.topLeft);
        final fullLocalRect = localTopLeft & globalRect.size;

        // Per user's brilliant suggestion, shrink the target to the middle 80%
        // to leave the top and bottom 10% exposed for reordering.
        final targetHeight = fullLocalRect.height * 0.8;
        final verticalPadding = (fullLocalRect.height - targetHeight) / 2.0;
        
        final targetRect = Rect.fromLTWH(
          fullLocalRect.left,
          fullLocalRect.top + verticalPadding,
          fullLocalRect.width,
          targetHeight,
        );

        return Positioned.fromRect(
          rect: targetRect,
          child: DragTarget<DragAndDropItem>(
            builder: (context, candidateData, rejectedData) {
              // This is a transparent container that just detects drops.
              return const SizedBox.expand();
            },
            onWillAcceptWithDetails: (details) {
              final draggedItem = details.data.child;
              if (draggedItem is _FolderListItem && draggedItem.folder.id == folderId) {
                return false;
              }
              ref.read(hoveredFolderIdProvider.notifier).state = folderId;
              return true;
            },
            onLeave: (data) {
              ref.read(hoveredFolderIdProvider.notifier).state = null;
            },
            onAcceptWithDetails: (details) {
              ref.read(hoveredFolderIdProvider.notifier).state = null;

              final incomingItem = details.data;
              dynamic draggedItemEntity;

              if (incomingItem.child is _FolderListItem) {
                draggedItemEntity = (incomingItem.child as _FolderListItem).folder;
              } else if (incomingItem.child is _TemplateListItem) {
                draggedItemEntity = (incomingItem.child as _TemplateListItem).template;
              }

              if (draggedItemEntity == null) return;

              ref.read(templatesAndFoldersActionsProvider).moveItemToFolder(
                    itemId: draggedItemEntity.id,
                    isFolder: draggedItemEntity is Folder,
                    sourceFolderId: currentFolderId,
                    targetFolderId: folderId,
                  );
            },
          ),
        );
      }).toList(),
    );
  }
}


// --- UI Components ---

class _FolderListItem extends ConsumerStatefulWidget {
  final Folder folder;
  const _FolderListItem({required this.folder, super.key});

  @override
  ConsumerState<_FolderListItem> createState() => _FolderListItemState();
}

class _FolderListItemState extends ConsumerState<_FolderListItem> {
  // --- Performance Optimization ---
  // All bounds reporting logic (_reportBounds, initState, didUpdateWidget, dispose,
  // and the post-frame callback in build) has been removed from this widget.
  // The responsibility is now centralized in the HomeScreen, which calculates
  // all folder positions at once when a drag starts. This prevents every
  // single folder item from triggering state updates on every frame.

  @override
  Widget build(BuildContext context) {
    final hoveredFolderId = ref.watch(hoveredFolderIdProvider);
    final isHighlighted = hoveredFolderId == widget.folder.id;
    final theme = Theme.of(context);

    return Container(
      decoration: isHighlighted
          ? BoxDecoration(
              border: Border.all(color: theme.colorScheme.primary, width: 2),
              borderRadius: BorderRadius.circular(12.0),
            )
          : null,
      child: InkWell(
        onTap: () => ref.read(folderNavigationStackProvider.notifier).push(widget.folder.id),
        borderRadius: BorderRadius.circular(12.0),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 8.0),
          child: Row(
            children: [
              Icon(Icons.folder_outlined, color: theme.colorScheme.primary),
              const SizedBox(width: 16),
              Expanded(child: Text(widget.folder.name, style: theme.textTheme.titleMedium)),
              IconButton(icon: const Icon(Icons.drive_file_rename_outline), tooltip: '重命名', onPressed: () => _showRenameFolderDialog(context, ref, widget.folder)),
              IconButton(icon: Icon(Icons.delete_outline, color: theme.colorScheme.error), tooltip: '删除', onPressed: () => _showDeleteFolderDialog(context, ref, widget.folder)),
            ],
          ),
        ),
      ),
    );
  }
}

class _TemplateListItem extends ConsumerWidget {
  final Template template;
  const _TemplateListItem({required this.template});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => context.push(AppRouter.applyTemplatePath, extra: template),
      borderRadius: BorderRadius.circular(12.0),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 8.0),
        child: Row(
          children: [
            Icon(Icons.article_outlined, color: theme.colorScheme.primary),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(template.name, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text('包含 ${template.fieldIds.length} 个字段', style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            IconButton(icon: const Icon(Icons.edit_outlined), tooltip: '编辑', onPressed: () {
              context.push('${AppRouter.createTemplatePath}/${template.id}');
            }),
            IconButton(icon: Icon(Icons.delete_outline, color: theme.colorScheme.error), tooltip: '删除', onPressed: () => _showDeleteTemplateConfirmation(context, ref, template)),
          ],
        ),
      ),
    );
  }
}

class _DragToParentNavBar extends ConsumerStatefulWidget {
  final String? currentFolderId;

  const _DragToParentNavBar({
    this.currentFolderId,
  });

  @override
  ConsumerState<_DragToParentNavBar> createState() => _DragToParentNavBarState();
}

class _DragToParentNavBarState extends ConsumerState<_DragToParentNavBar> {
  bool _isHighlighted = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final navigationStack = ref.watch(folderNavigationStackProvider);
    final parentFolderId = navigationStack.length > 1 ? navigationStack[navigationStack.length - 2] : null;


    return DragTarget<DragAndDropItem>(
      builder: (context, candidateData, rejectedData) {
        return Container(
          height: 48.0,
          decoration: BoxDecoration(
            color: _isHighlighted
                ? theme.colorScheme.primaryContainer
                : theme.colorScheme.surfaceContainerHighest.withAlpha((255 * 0.5).round()),
            border: Border(bottom: BorderSide(color: theme.dividerColor)),
          ),
          child: _BreadcrumbTrail(isHighlighted: _isHighlighted),
        );
      },
      onWillAcceptWithDetails: (details) {
        setState(() {
          _isHighlighted = true;
        });
        return true;
      },
      onLeave: (data) {
        setState(() {
          _isHighlighted = false;
        });
      },
      onAcceptWithDetails: (details) {
        setState(() {
          _isHighlighted = false;
        });

        if (widget.currentFolderId == null) return;

        final item = details.data;
        dynamic entity;
        
        final child = item.child;
        if (child is _FolderListItem) {
          entity = child.folder;
        } else if (child is _TemplateListItem) {
          entity = child.template;
        }

        if (entity == null) return;

        ref.read(templatesAndFoldersActionsProvider).moveItemToFolder(
              itemId: entity.id,
              isFolder: entity is Folder,
              sourceFolderId: widget.currentFolderId!,
              targetFolderId: parentFolderId,
            );
      },
    );
  }
}

class _BreadcrumbTrail extends ConsumerWidget {
  final bool isHighlighted;
  const _BreadcrumbTrail({this.isHighlighted = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pathAsync = ref.watch(folderPathProvider);
    final currentFolderId = ref.watch(currentFolderIdProvider);
    final theme = Theme.of(context);

    return pathAsync.when(
      data: (path) {
        if (isHighlighted) {
           return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0),
            child: Row(
              children: [
                const Icon(Icons.move_up, size: 20.0),
                const SizedBox(width: 8),
                Text('上移到 "${path[path.length - 2]?.name ?? '根目录'}"'),
              ],
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 12.0),
          scrollDirection: Axis.horizontal,
          itemCount: path.length,
          separatorBuilder: (context, index) =>
              const Icon(Icons.chevron_right, color: Colors.grey),
          itemBuilder: (context, index) {
            final folder = path[index];
            final folderName = folder?.name ?? '根目录';
            final folderId = folder?.id;
            final isCurrent = folderId == currentFolderId;

            return InkWell(
              onTap: () {
                if (!isCurrent) {
                  ref.read(folderNavigationStackProvider.notifier).popTo(index);
                }
              },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                alignment: Alignment.center,
                child: Text(
                  folderName,
                  style: TextStyle(
                    fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                    color: isCurrent
                        ? theme.colorScheme.primary
                        : theme.textTheme.bodyLarge?.color,
                  ),
                ),
              ),
            );
          },
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (err, stack) => const SizedBox.shrink(),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.style_outlined, size: 80, color: theme.colorScheme.secondary),
          const SizedBox(height: 16),
          Text('空空如也', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text('创建一个模板或文件夹来开始吧！', style: theme.textTheme.bodyMedium, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

// --- Dialogs (保持不变) ---

Future<void> _showCreateFolderDialog(BuildContext context, WidgetRef ref) async {
  final controller = TextEditingController();
  final folderName = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('新建文件夹'),
      content: TextField(controller: controller, autofocus: true, decoration: const InputDecoration(hintText: '文件夹名称')),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.of(context).pop(controller.text), child: const Text('创建')),
      ],
    ),
  );
  if (folderName != null && folderName.isNotEmpty) {
    await ref.read(templatesAndFoldersActionsProvider).createFolder(folderName, parentId: ref.read(currentFolderIdProvider));
  }
}

Future<void> _showDeleteTemplateConfirmation(BuildContext context, WidgetRef ref, Template template) async {
  final bool? confirmed = await showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('确认删除'),
      content: Text('您确定要删除模板 "${template.name}" 吗？此操作无法撤销。'),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('取消')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('删除'),
        ),
      ],
    ),
  );
  if (confirmed == true) {
    try {
      await ref.read(templatesAndFoldersActionsProvider).deleteTemplate(template.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('模板 "${template.name}" 已删除')));
      }
    } catch (e) {
       if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('删除失败: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }
}

Future<void> _showRenameFolderDialog(BuildContext context, WidgetRef ref, Folder folder) async {
  final controller = TextEditingController(text: folder.name);
  final newName = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('重命名文件夹'),
      content: TextField(controller: controller, autofocus: true),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.of(context).pop(controller.text), child: const Text('重命名')),
      ],
    ),
  );
  if (newName != null && newName.isNotEmpty && newName != folder.name) {
    await ref.read(templatesAndFoldersActionsProvider).updateFolder(folder.id, newName);
  }
}

Future<void> _showDeleteFolderDialog(BuildContext context, WidgetRef ref, Folder folder) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('确认删除'),
      content: Text('您确定要删除文件夹 "${folder.name}" 吗？\n\n注意：只有空文件夹才能被删除。'),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('取消')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('删除'),
        ),
      ],
    ),
  );
  if (confirmed == true && context.mounted) {
    try {
      await ref.read(templatesAndFoldersActionsProvider).deleteFolder(folder.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('文件夹 "${folder.name}" 已删除')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('删除失败: ${e.toString().replaceFirst("Exception: ", "")}'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }
}
