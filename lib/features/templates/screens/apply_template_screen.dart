import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_ocr/core/router/app_router.dart';
import 'package:image_ocr/features/processing/models/image_processing_state.dart';
import 'package:image_ocr/features/processing/providers/image_processing_provider.dart';
import 'package:image_ocr/features/templates/models/template.dart';
import 'package:image_ocr/features/templates/providers/template_providers.dart';
import 'package:image_ocr/features/templates/widgets/template_selection_dialog.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

class ApplyTemplateScreen extends ConsumerStatefulWidget {
  final Template? initialTemplate;
  const ApplyTemplateScreen({super.key, this.initialTemplate});

  @override
  ConsumerState<ApplyTemplateScreen> createState() => _ApplyTemplateScreenState();
}

class _ApplyTemplateScreenState extends ConsumerState<ApplyTemplateScreen> {
  final List<AssetEntity> _targetAssets = [];

  @override
  void initState() {
    super.initState();
    // 使用 Future.microtask 延迟状态更新，以避免在构建期间修改 Provider
    Future.microtask(() {
      final notifier = ref.read(selectedTemplatesForProcessingProvider.notifier);
      if (widget.initialTemplate != null) {
        notifier.state = {widget.initialTemplate!};
      } else {
        notifier.state = {};
      }
    });
  }

  Future<void> _pickMultipleImages() async {
    final status = await Permission.photos.request();
    if (!status.isGranted) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('需要相册权限')));
      return;
    }

    if (!mounted) return;
    final selectedAssets = await showDialog<List<AssetEntity>>(
      context: context,
      builder: (context) => const _AssetPicker(),
    );

    if (selectedAssets != null) {
      setState(() {
        _targetAssets.addAll(selectedAssets);
        // 去重
        final ids = _targetAssets.map((e) => e.id).toSet();
        _targetAssets.retainWhere((e) => ids.remove(e.id));
      });
    }
  }

  Future<void> _addTemplates() async {
    final selectedTemplates = ref.read(selectedTemplatesForProcessingProvider);
    
    final newlySelected = await showDialog<List<Template>>(
      context: context,
      builder: (context) => TemplateSelectionDialog(
        alreadySelectedIds: selectedTemplates.map((t) => t.id).toSet(),
      ),
    );

    if (newlySelected != null && newlySelected.isNotEmpty) {
      final notifier = ref.read(selectedTemplatesForProcessingProvider.notifier);
      // 合并现有选择和新选择
      notifier.state = {...notifier.state, ...newlySelected};
    }
  }

  Future<void> _startProcessing() async {
    final selectedTemplates = ref.read(selectedTemplatesForProcessingProvider);
    if (_targetAssets.isEmpty || selectedTemplates.isEmpty) return;

    // 从 AssetEntity 获取文件路径
    final files = await Future.wait(_targetAssets.map((asset) => asset.file));
    final paths = files.where((file) => file != null).map((file) => file!.path).toList();
    
    if (paths.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('无法获取图片文件')));
      return;
    }

    ref.read(imageProcessingProvider.notifier).processBatch(
          templates: selectedTemplates.toList(),
          targetImagePaths: paths,
        );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<ImageProcessingState>(imageProcessingProvider, (previous, next) {
      if (previous?.isProcessing == true && !next.isProcessing) {
        _deleteProcessedOriginals(next);

        final hasSuccess = next.results.isNotEmpty;
        final hasFailure = next.failedPaths.isNotEmpty;

        if (!hasSuccess && hasFailure) {
          // All failed
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('所有图片处理失败')),
            );
          }
        } else if (hasSuccess) {
          // Some or all succeeded
          if (hasFailure && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('${next.failedPaths.length} 张图片处理失败')),
            );
          }
          context.pushReplacement(AppRouter.batchPreviewPath, extra: next);
        }
      }
    });

    final processingState = ref.watch(imageProcessingProvider);
    final selectedTemplates = ref.watch(selectedTemplatesForProcessingProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('应用模板')),
      body: Column(
        children: [
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // --- 左侧: 模板列表 ---
                Expanded(
                  child: _TemplatePanel(
                    templates: selectedTemplates.toList(),
                    onRemove: (index) {
                      final notifier = ref.read(selectedTemplatesForProcessingProvider.notifier);
                      final currentList = notifier.state.toList();
                      currentList.removeAt(index);
                      notifier.state = currentList.toSet();
                    },
                    onReorder: (oldIndex, newIndex) {
                      final notifier = ref.read(selectedTemplatesForProcessingProvider.notifier);
                      final currentList = notifier.state.toList();
                      if (newIndex > oldIndex) newIndex -= 1;
                      final item = currentList.removeAt(oldIndex);
                      currentList.insert(newIndex, item);
                      notifier.state = currentList.toSet();
                    },
                  ),
                ),
                const VerticalDivider(width: 1),
                // --- 右侧: 目标图片 ---
                Expanded(
                  child: _TargetImagePanel(
                    assets: _targetAssets,
                    onRemove: (index) => setState(() => _targetAssets.removeAt(index)),
                  ),
                ),
              ],
            ),
          ),
          if (processingState.isProcessing)
            const _ProcessingIndicator()
          else
            _ActionFooter(
              onAddImages: _pickMultipleImages,
              onAddTemplates: _addTemplates,
              onProcess: _targetAssets.isNotEmpty && selectedTemplates.isNotEmpty ? _startProcessing : null,
            ),
        ],
      ),
    );
  }

  /// 删除处理成功的原始图片
  Future<void> _deleteProcessedOriginals(ImageProcessingState processingState) async {
    final List<AssetEntity> successfulAssets = [];
    for (final asset in _targetAssets) {
      final file = await asset.file;
      if (file != null && !processingState.failedPaths.contains(file.path)) {
        successfulAssets.add(asset);
      }
    }

    if (successfulAssets.isEmpty) {
      return;
    }

    final status = await Permission.manageExternalStorage.request();
    if (!status.isGranted) {
      return;
    }

    List<String> deletedAssetIds = [];

    for (final asset in successfulAssets) {
      try {
        final file = await asset.file;
        if (file != null && await file.exists()) {
          await file.delete();
          deletedAssetIds.add(asset.id);
        } else {
          // Asset file might have been deleted from the device.
        }
      } catch (e) {
        // Ignore errors for single asset deletion failures.
      }
    }

    if (mounted) {
      setState(() {
        _targetAssets.removeWhere((asset) => deletedAssetIds.contains(asset.id));
      });
    }
  }
}

// --- Panels ---

class _TemplatePanel extends StatelessWidget {
  final List<Template> templates;
  final void Function(int) onRemove;
  final void Function(int, int) onReorder;

  const _TemplatePanel({
    required this.templates,
    required this.onRemove,
    required this.onReorder,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text('模板', style: Theme.of(context).textTheme.titleLarge),
        ),
        Expanded(
          child: ReorderableListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            itemCount: templates.length,
            itemBuilder: (context, index) {
              final template = templates[index];
              return _TemplateTag(
                key: ValueKey(template.id),
                template: template,
                onRemove: () => onRemove(index),
              );
            },
            onReorder: onReorder,
          ),
        ),
      ],
    );
  }
}

class _TargetImagePanel extends StatelessWidget {
  final List<AssetEntity> assets;
  final void Function(int) onRemove;

  const _TargetImagePanel({required this.assets, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text('目标图片', style: Theme.of(context).textTheme.titleLarge),
        ),
        Expanded(
          child: assets.isEmpty
              ? const Center(child: Text('请添加目标图片'))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  itemCount: assets.length,
                  itemBuilder: (context, index) {
                    return _ImagePreviewItem(
                      asset: assets[index],
                      onRemove: () => onRemove(index),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// --- UI Components ---

class _TemplateTag extends StatelessWidget {
  final Template template;
  final VoidCallback onRemove;

  const _TemplateTag({super.key, required this.template, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8.0),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
        child: Row(
          children: [
            Expanded(
              child: Text(template.name, style: Theme.of(context).textTheme.titleMedium),
            ),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: onRemove,
              tooltip: '移除模板',
            ),
          ],
        ),
      ),
    );
  }
}

class _ImagePreviewItem extends StatelessWidget {
  final AssetEntity asset;
  final VoidCallback onRemove;

  const _ImagePreviewItem({required this.asset, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8.0),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          GestureDetector(
            onTap: () async {
              final file = await asset.file;
              if (file != null && context.mounted) {
                context.push(AppRouter.previewPath, extra: file.path);
              }
            },
            child: AspectRatio(
              aspectRatio: 0.5, // 严格遵循 1:2 的宽高比
              child: AssetEntityImage(
                asset,
                isOriginal: false,
                fit: BoxFit.cover,
              ),
            ),
          ),
          Positioned(
            top: 4,
            right: 4,
            child: IconButton(
              icon: const Icon(Icons.close),
              onPressed: onRemove,
              style: IconButton.styleFrom(
                backgroundColor: Colors.black.withAlpha((255 * 0.5).round()),
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionFooter extends StatelessWidget {
  final VoidCallback onAddImages;
  final VoidCallback onAddTemplates;
  final VoidCallback? onProcess;

  const _ActionFooter({
    required this.onAddImages,
    required this.onAddTemplates,
    this.onProcess,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: const Text('添加图片'),
                onPressed: onAddImages,
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.icon(
                icon: const Icon(Icons.add_task_outlined),
                label: const Text('添加模板'),
                onPressed: onAddTemplates,
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.icon(
                icon: const Icon(Icons.play_arrow_outlined),
                label: const Text('开始处理'),
                onPressed: onProcess,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: onProcess != null ? Colors.green : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProcessingIndicator extends ConsumerWidget {
  const _ProcessingIndicator();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(imageProcessingProvider);
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LinearProgressIndicator(value: state.progress),
          const SizedBox(height: 8),
          Text('正在处理 ${state.processedCount} / ${state.totalCount}...'),
        ],
      ),
    );
  }
}


// --- Custom Asset Picker Dialog ---

class _AssetPicker extends StatefulWidget {
  const _AssetPicker();

  @override
  State<_AssetPicker> createState() => _AssetPickerState();
}

class _AssetPickerState extends State<_AssetPicker> {
  List<AssetEntity> _assets = [];
  final Set<AssetEntity> _selectedAssets = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchAssets();
  }

  Future<void> _fetchAssets() async {
    // 每次获取时都清除旧的缓存，确保获取的是最新数据
    await PhotoManager.clearFileCache();

    final albums = await PhotoManager.getAssetPathList(type: RequestType.image);
    if (albums.isEmpty) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    // 通常第一个相册是“最近”或“所有图片”
    final recentAlbum = albums.first;
    final assets = await recentAlbum.getAssetListPaged(page: 0, size: 200); // 增加加载数量
    if (mounted) {
      setState(() {
        _assets = assets;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('选择图片'),
      contentPadding: const EdgeInsets.fromLTRB(0, 20, 0, 24),
      content: SizedBox(
        width: double.maxFinite,
        height: 500,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _assets.isEmpty
                ? const Center(child: Text('相册中没有图片'))
                : GridView.builder(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 4,
                      mainAxisSpacing: 4,
                    ),
                    itemCount: _assets.length,
                    itemBuilder: (context, index) {
                      final asset = _assets[index];
                      final isSelected = _selectedAssets.contains(asset);
                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            if (isSelected) {
                              _selectedAssets.remove(asset);
                            } else {
                              _selectedAssets.add(asset);
                            }
                          });
                        },
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            AssetEntityImage(
                              asset,
                              isOriginal: false,
                              fit: BoxFit.cover,
                            ),
                            if (isSelected)
                              Container(
                                color: Colors.black.withAlpha((255 * 0.5).round()),
                                child: const Icon(Icons.check_circle, color: Colors.white),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.of(context).pop(_selectedAssets.toList()), child: const Text('确认')),
      ],
    );
  }
}