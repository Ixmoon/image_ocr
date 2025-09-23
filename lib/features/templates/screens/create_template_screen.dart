import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:image/image.dart' as img;
import 'package:image_ocr/core/router/app_router.dart';
import 'package:image_ocr/features/processing/services/ocr_service.dart';
import 'package:image_ocr/features/processing/utils/anchor_finder.dart';
import 'package:image_ocr/features/templates/models/template_field.dart';
import 'package:image_ocr/features/templates/providers/template_providers.dart';
import 'package:image_ocr/widgets/interactive_image_viewer.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';

// --- Main Screen Widget ---
class CreateTemplateScreen extends ConsumerWidget {
  final String? templateId;
  const CreateTemplateScreen({super.key, this.templateId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isEditMode = templateId != null;
    if (isEditMode) {
      final templateAsync = ref.watch(templateByIdProvider(templateId!));
      return templateAsync.when(
        loading: () => const _LoadingScaffold(title: '编辑模板'),
        error: (err, stack) => _ErrorScaffold(title: '编辑模板', error: err),
        data: (template) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (ref.read(templateCreationProvider).id != template.id) {
              ref.read(templateCreationProvider.notifier).loadForEditing(template);
            }
          });
          return const _CreateTemplateView(isEdit: true);
        },
      );
    } else {
      return const _CreateTemplateView(isEdit: false);
    }
  }
}

// --- Main View (Stateful) ---
class _CreateTemplateView extends ConsumerStatefulWidget {
  final bool isEdit;
  const _CreateTemplateView({required this.isEdit});

  @override
  ConsumerState<_CreateTemplateView> createState() => _CreateTemplateViewState();
}

class _CreateTemplateViewState extends ConsumerState<_CreateTemplateView> {
  // State
  bool _isPickingImage = false;
  Rect? _previewLabelRect;
  Rect? _previewValueRect;
  bool _isOcrLoading = false;
  // [修正] 移除OCR缓存，这是一个错误的设计，每次预览都应该重新执行OCR

  @override
  void initState() {
    super.initState();
    if (!widget.isEdit) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final currentFolderId = ref.read(currentFolderIdProvider);
        ref.read(templateCreationProvider.notifier).createNew(folderId: currentFolderId);
      });
    }
  }

  // --- Methods ---

  Future<void> _pickSourceImage() async {
    if (_isPickingImage) return;
    final status = await Permission.photos.request();
    if (!status.isGranted && !status.isLimited) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('需要相册权限')));
      return;
    }
    setState(() => _isPickingImage = true);
    try {
      final pickedFile = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (pickedFile != null) {
        ref.read(templateCreationProvider.notifier).setSourceImage(pickedFile.path);
      }
    } finally {
      if (mounted) setState(() => _isPickingImage = false);
    }
  }

  Future<void> _previewField(String fieldName) async {
    if (fieldName.isEmpty) return;
    setState(() {
      _isOcrLoading = true;
      _previewLabelRect = null;
      _previewValueRect = null;
    });

    try {
      final sourceImagePath = ref.read(templateCreationProvider).sourceImagePath;
      if (sourceImagePath.isEmpty) {
        throw Exception('源图片路径为空');
      }

      // [最终架构] 直接调用已包含预处理的OcrService
      final ocrResult = await ref.read(ocrServiceProvider).processImage(sourceImagePath);


      final foundLine = findAnchorLine(ocrResult: ocrResult, searchText: fieldName);
      
      if (foundLine != null) {
        
        final imageBytes = await File(sourceImagePath).readAsBytes();
        final image = img.decodeImage(imageBytes);
        if (image == null) throw Exception('无法解码图片以获取尺寸');
        final imageSize = Size(image.width.toDouble(), image.height.toDouble());

        final labelRect = foundLine.boundingBox;
        final valueRect = findValueRectForAnchorLine(
          anchorLine: foundLine,
          imageSize: imageSize,
        );

        setState(() {
          _previewLabelRect = labelRect;
          _previewValueRect = valueRect;
        });

      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('在图片中未找到该文本')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('OCR预览失败: $e')));
    } finally {
      if (mounted) setState(() => _isOcrLoading = false);
    }
  }

  void _clearPreview() {
    setState(() {
      _previewLabelRect = null;
      _previewValueRect = null;
    });
  }

  Future<void> _addField() async {
    final fieldNameController = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('添加新字段'),
        content: TextField(
          controller: fieldNameController,
          autofocus: true,
          decoration: const InputDecoration(labelText: '字段名'),
        ),
        actions: [
          TextButton(onPressed: () => context.pop(), child: const Text('取消')),
          FilledButton(onPressed: () => context.pop(fieldNameController.text), child: const Text('添加')),
        ],
      ),
    );

    if (name != null && name.isNotEmpty && mounted) {
      final newField = TemplateField(id: const Uuid().v4(), name: name);
      await Hive.box<TemplateField>('template_fields').put(newField.id, newField);
      ref.read(templateCreationProvider.notifier).addField(newField.id);
    }
  }

  // --- Build ---
  @override
  Widget build(BuildContext context) {
    final templateState = ref.watch(templateCreationProvider);
    final templateNotifier = ref.read(templateCreationProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEdit ? '编辑模板' : '创建新模板'),
        actions: [
          if (templateState.sourceImagePath.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.save),
              tooltip: '保存模板',
              onPressed: () async {
                await templateNotifier.save();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('模板已保存'), duration: Duration(seconds: 2)),
                  );
                }
              },
            ),
        ],
      ),
      body: templateState.sourceImagePath.isEmpty
          ? _SourceImagePicker(onPressed: _pickSourceImage)
          : _TemplateEditor(
              onAddField: _addField,
              onPreviewField: _previewField,
              onClearPreview: _clearPreview,
              previewLabelRect: _previewLabelRect,
              previewValueRect: _previewValueRect,
              isOcrLoading: _isOcrLoading,
            ),
      floatingActionButton: templateState.sourceImagePath.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: () async {
                // 保存并跳转
                await templateNotifier.save();
                // 获取最新的模板状态以传递
                final latestTemplate = ref.read(templateCreationProvider);
                if (context.mounted) {
                  context.push(AppRouter.applyTemplatePath, extra: latestTemplate);
                }
              },
              icon: const Icon(Icons.layers_outlined),
              label: const Text('应用模板'),
            )
          : null,
    );
  }
}

// --- UI Components ---

class _TemplateEditor extends ConsumerWidget {
  final VoidCallback onAddField;
  final Future<void> Function(String) onPreviewField;
  final VoidCallback onClearPreview;
  final Rect? previewLabelRect;
  final Rect? previewValueRect;
  final bool isOcrLoading;

  const _TemplateEditor({
    required this.onAddField,
    required this.onPreviewField,
    required this.onClearPreview,
    this.previewLabelRect,
    this.previewValueRect,
    required this.isOcrLoading,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final template = ref.watch(templateCreationProvider);
    final theme = Theme.of(context);
    final fieldsBox = Hive.box<TemplateField>('template_fields');

    return Column(
      children: [
        Expanded(
          flex: 2,
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: GestureDetector(
              onTap: () async {
                final newPath = await context.push<String>(
                  AppRouter.previewPath,
                  extra: {
                    'imagePath': template.sourceImagePath,
                    'canReplace': true,
                  },
                );
                if (newPath != null && context.mounted) {
                  ref.read(templateCreationProvider.notifier).setSourceImage(newPath);
                }
              },
              child: InteractiveImageViewer(
                key: ValueKey(template.sourceImagePath),
                imagePath: template.sourceImagePath,
                labelRect: previewLabelRect,
                highlightRects: previewValueRect != null ? [previewValueRect!] : [],
              ),
            ),
          ),
        ),
        if (isOcrLoading) const LinearProgressIndicator(),
        Expanded(
          flex: 3,
          child: ListView(
            padding: const EdgeInsets.all(16.0),
            children: [
              TextFormField(
                initialValue: template.name,
                decoration: const InputDecoration(labelText: '模板名称', border: OutlineInputBorder()),
                onChanged: (value) => ref.read(templateCreationProvider.notifier).updateName(value),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('字段', style: theme.textTheme.titleLarge),
                  FilledButton.tonalIcon(
                    icon: const Icon(Icons.add),
                    label: const Text('添加字段'),
                    onPressed: onAddField,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ValueListenableBuilder(
                valueListenable: fieldsBox.listenable(),
                builder: (context, Box<TemplateField> box, _) {
                  final fields = template.fieldIds.map((id) => box.get(id)).where((f) => f != null).cast<TemplateField>().toList();
                  if (fields.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24.0),
                      child: Center(child: Text('请添加至少一个字段')),
                    );
                  }
                  return Column(
                    children: fields.map((field) => _FieldListItem(
                      field: field,
                      onPreview: () => onPreviewField(field.name),
                      onClearPreview: onClearPreview,
                    )).toList(),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FieldListItem extends ConsumerWidget {
  final TemplateField field;
  final VoidCallback onPreview;
  final VoidCallback onClearPreview;

  const _FieldListItem({required this.field, required this.onPreview, required this.onClearPreview});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4.0),
      child: ListTile(
        leading: IconButton(
          icon: const Icon(Icons.search),
          tooltip: '预览此字段',
          onPressed: onPreview,
        ),
        title: Text(field.name),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline),
          onPressed: () {
            ref.read(templateCreationProvider.notifier).removeField(field.id);
            onClearPreview();
          },
        ),
      ),
    );
  }
}

// --- Helper Widgets ---
class _SourceImagePicker extends StatelessWidget {
  final VoidCallback onPressed;
  const _SourceImagePicker({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.add_photo_alternate_outlined, size: 80, color: Theme.of(context).colorScheme.secondary),
          const SizedBox(height: 16),
          Text('第一步：选择源图片', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 24),
          FilledButton(onPressed: onPressed, child: const Text('从相册选择')),
        ],
      ),
    );
  }
}

class _LoadingScaffold extends StatelessWidget {
  final String title;
  const _LoadingScaffold({required this.title});
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: Text(title)), body: const Center(child: CircularProgressIndicator()));
}

class _ErrorScaffold extends StatelessWidget {
  final String title;
  final Object error;
  const _ErrorScaffold({required this.title, required this.error});
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: Text(title)), body: Center(child: Text('加载失败: $error')));
}