import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_ocr/core/router/app_router.dart';
import 'package:image_ocr/features/processing/models/image_processing_state.dart';
import 'package:image_ocr/features/processing/providers/image_processing_provider.dart';
import 'package:image_ocr/features/templates/models/folder.dart';
import 'package:image_ocr/features/templates/models/template.dart';
import 'package:image_ocr/features/templates/providers/template_providers.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

class ApplyTemplateScreen extends ConsumerStatefulWidget {
  final Template? initialTemplate;
  const ApplyTemplateScreen({super.key, this.initialTemplate});

  @override
  ConsumerState<ApplyTemplateScreen> createState() => _ApplyTemplateScreenState();
}

class _ApplyTemplateScreenState extends ConsumerState<ApplyTemplateScreen> {
  late List<Template> _selectedTemplates;
  List<String> _targetImagePaths = [];

  @override
  void initState() {
    super.initState();
    _selectedTemplates = widget.initialTemplate != null ? [widget.initialTemplate!] : [];
  }

  Future<void> _pickMultipleImages() async {
    final status = await Permission.photos.request();
    if (!status.isGranted && !status.isLimited) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('需要相册权限')));
      return;
    }
    final pickedFiles = await ImagePicker().pickMultiImage();
    setState(() {
      _targetImagePaths = [..._targetImagePaths, ...pickedFiles.map((f) => f.path)];
    });
  }

  Future<void> _addTemplates() async {
    final newlySelected = await showDialog<List<Template>>(
      context: context,
      builder: (context) => _NavigableTemplateSelectionDialog(
        alreadySelectedIds: _selectedTemplates.map((t) => t.id).toSet(),
      ),
    );

    if (newlySelected != null && newlySelected.isNotEmpty) {
      setState(() {
        _selectedTemplates.addAll(newlySelected);
      });
    }
  }

  void _startProcessing() {
    if (_targetImagePaths.isEmpty || _selectedTemplates.isEmpty) return;
    ref.read(imageProcessingProvider.notifier).processBatch(
          templates: _selectedTemplates,
          targetImagePaths: _targetImagePaths,
        );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<ImageProcessingState>(imageProcessingProvider, (previous, next) {
      if (previous?.isProcessing == true && !next.isProcessing) {
        if (next.results.isNotEmpty || next.failedPaths.isNotEmpty) {
          context.pushReplacement(AppRouter.batchPreviewPath, extra: next);
        }
      }
    });

    final processingState = ref.watch(imageProcessingProvider);

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
                    templates: _selectedTemplates,
                    onRemove: (index) => setState(() => _selectedTemplates.removeAt(index)),
                    onReorder: (oldIndex, newIndex) {
                      setState(() {
                        if (newIndex > oldIndex) newIndex -= 1;
                        final item = _selectedTemplates.removeAt(oldIndex);
                        _selectedTemplates.insert(newIndex, item);
                      });
                    },
                  ),
                ),
                const VerticalDivider(width: 1),
                // --- 右侧: 目标图片 ---
                Expanded(
                  child: _TargetImagePanel(
                    imagePaths: _targetImagePaths,
                    onRemove: (index) => setState(() => _targetImagePaths.removeAt(index)),
                  ),
                ),
              ],
            ),
          ),
          if (processingState.isProcessing)
            _ProcessingIndicator()
          else
            _ActionFooter(
              onAddImages: _pickMultipleImages,
              onAddTemplates: _addTemplates,
              onProcess: _targetImagePaths.isNotEmpty && _selectedTemplates.isNotEmpty ? _startProcessing : null,
            ),
        ],
      ),
    );
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
  final List<String> imagePaths;
  final void Function(int) onRemove;

  const _TargetImagePanel({required this.imagePaths, required this.onRemove});

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
          child: imagePaths.isEmpty
              ? const Center(child: Text('请添加目标图片'))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  itemCount: imagePaths.length,
                  itemBuilder: (context, index) {
                    return _ImagePreviewItem(
                      path: imagePaths[index],
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
  final String path;
  final VoidCallback onRemove;

  const _ImagePreviewItem({required this.path, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8.0),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          GestureDetector(
            onTap: () => context.push(AppRouter.previewPath, extra: path),
            child: AspectRatio(
              aspectRatio: 0.5, // 严格遵循 1:2 的宽高比
              child: Image.file(
                File(path),
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

class _NavigableTemplateSelectionDialog extends ConsumerStatefulWidget {
  final Set<String> alreadySelectedIds;
  const _NavigableTemplateSelectionDialog({required this.alreadySelectedIds});

  @override
  ConsumerState<_NavigableTemplateSelectionDialog> createState() => _NavigableTemplateSelectionDialogState();
}

class _NavigableTemplateSelectionDialogState extends ConsumerState<_NavigableTemplateSelectionDialog> {
  late final List<String?> _navigationStack;
  final _selectedTemplatesInDialog = <Template>{};

  @override
  void initState() {
    super.initState();
    _navigationStack = [ref.read(currentFolderIdProvider)];
  }

  @override
  Widget build(BuildContext context) {
    final currentFolderId = _navigationStack.last;
    final contentsAsync = ref.watch(folderContentsProvider(currentFolderId));
    final pathAsync = ref.watch(folderPathProvider);

    return AlertDialog(
      title: const Text('选择模板'),
      contentPadding: const EdgeInsets.fromLTRB(0, 20, 0, 24),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 30,
              child: pathAsync.when(
                data: (path) => ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  scrollDirection: Axis.horizontal,
                  itemCount: path.length,
                  separatorBuilder: (context, index) => const Icon(Icons.chevron_right, color: Colors.grey),
                  itemBuilder: (context, index) {
                    final folder = path[index];
                    return InkWell(
                      onTap: () => setState(() => _navigationStack.removeRange(index + 1, _navigationStack.length)),
                      child: Center(child: Text(folder?.name ?? '根目录')),
                    );
                  },
                ),
                loading: () => const SizedBox.shrink(),
                error: (e, s) => const SizedBox.shrink(),
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: contentsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (err, stack) => Center(child: Text('加载失败: $err')),
                data: (contents) {
                  if (contents.isEmpty) return const Center(child: Text('此文件夹为空'));
                  return ListView.builder(
                    itemCount: contents.length,
                    itemBuilder: (context, index) {
                      final item = contents[index];
                      if (item is Folder) {
                        return ListTile(
                          leading: const Icon(Icons.folder_outlined),
                          title: Text(item.name),
                          onTap: () => setState(() => _navigationStack.add(item.id)),
                        );
                      } else if (item is Template) {
                        final template = item;
                        final isAlreadySelected = widget.alreadySelectedIds.contains(template.id);
                        final isSelectedInDialog = _selectedTemplatesInDialog.any((t) => t.id == template.id);
                        return CheckboxListTile(
                          title: Text(template.name),
                          value: isSelectedInDialog,
                          enabled: !isAlreadySelected,
                          onChanged: (bool? value) {
                            if (isAlreadySelected) return;
                            setState(() {
                              if (value == true) {
                                _selectedTemplatesInDialog.add(template);
                              } else {
                                _selectedTemplatesInDialog.removeWhere((t) => t.id == template.id);
                              }
                            });
                          },
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => context.pop(), child: const Text('取消')),
        FilledButton(onPressed: () => context.pop(_selectedTemplatesInDialog.toList()), child: const Text('确认添加')),
      ],
    );
  }
}