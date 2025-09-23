import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_clone_tool/core/router/app_router.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:image_clone_tool/features/templates/models/template.dart';
import 'package:image_clone_tool/features/templates/models/template_field.dart';
import 'package:image_clone_tool/features/templates/providers/template_providers.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

// 创建/编辑模板的屏幕
class CreateTemplateScreen extends ConsumerStatefulWidget {
  final String? templateId; // 用于区分是创建还是编辑
  const CreateTemplateScreen({super.key, this.templateId});

  @override
  ConsumerState<CreateTemplateScreen> createState() => _CreateTemplateScreenState();
}

class _CreateTemplateScreenState extends ConsumerState<CreateTemplateScreen> {
  bool _isPickingImage = false;

  @override
  void initState() {
    super.initState();
    // 使用 addPostFrameCallback 确保 build 完成后安全地与 provider 交互
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 如果是编辑模式，则加载现有模板数据
      if (widget.templateId != null) {
        // 从已加载的模板列表中查找
        Template? templateToEdit;
        final templates = ref.read(templatesProvider).asData?.value;
        if (templates != null) {
          for (final t in templates) {
            if (t.id == widget.templateId) {
              templateToEdit = t;
              break;
            }
          }
        }
        
        if (templateToEdit != null) {
          // 使用找到的模板来初始化创建/编辑状态
          ref.read(templateCreationProvider.notifier).loadForEditing(templateToEdit);
        }
      } else {
        // 如果是创建模式，确保状态是清空的
        ref.read(templateCreationProvider.notifier).createNew();
      }
    });
  }

  Future<void> _pickSourceImage() async {
    if (_isPickingImage) return;

    // 1. 请求权限
    final status = await Permission.photos.request();
    if (!status.isGranted && !status.isLimited) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('需要相册权限才能选择图片')),
        );
      }
      return;
    }

    setState(() { _isPickingImage = true; });

    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(source: ImageSource.gallery);
      if (pickedFile != null && mounted) {
        ref.read(templateCreationProvider.notifier).setSourceImage(pickedFile.path);
      }
    } finally {
      if (mounted) {
        setState(() { _isPickingImage = false; });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final templateState = ref.watch(templateCreationProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.templateId == null ? '创建新模板' : '编辑模板'),
        actions: [
          // 只有在源图片已选择后才显示保存按钮
          if (templateState?.sourceImagePath != null)
            IconButton(
              icon: const Icon(Icons.check),
              tooltip: '保存模板',
              onPressed: () async {
                await ref.read(templateCreationProvider.notifier).save();
                if (context.mounted) context.pop(); // 保存后返回主页
              },
            ),
        ],
      ),
      body: templateState?.sourceImagePath == null
          // 步骤1: 选择源图片
          ? _SourceImagePicker(onPressed: _pickSourceImage)
          // 步骤2: 编辑模板名称和字段
          : _TemplateEditor(key: ValueKey(templateState!.id)),
    );
  }
}

// 选择源图片的UI组件
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
          const SizedBox(height: 8),
          const Text('选择一张图片作为模板的基础'),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: onPressed,
            child: const Text('从相册选择'),
          ),
        ],
      ),
    );
  }
}

// 模板编辑器UI组件
class _TemplateEditor extends ConsumerWidget {
  const _TemplateEditor({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final template = ref.watch(templateCreationProvider)!;
    final theme = Theme.of(context);
    final fieldsBox = Hive.box<TemplateField>('template_fields');

    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        // 源图片预览
        Text('源图片', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: () => context.push(AppRouter.previewPath, extra: template.sourceImagePath),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12.0),
            child: AspectRatio(
              aspectRatio: 9 / 16, // 强制为竖直长方形
              child: Container(
                color: Colors.black87,
                child: Image.file(
                  File(template.sourceImagePath),
                  fit: BoxFit.contain, // 确保图片完整显示不拉伸
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),

        // 模板名称输入框
        TextFormField(
          initialValue: template.name,
          decoration: const InputDecoration(
            labelText: '模板名称',
            border: OutlineInputBorder(),
          ),
          onChanged: (value) {
            ref.read(templateCreationProvider.notifier).updateName(value);
          },
        ),
        const SizedBox(height: 24),

        // 字段列表
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('字段', style: theme.textTheme.titleLarge),
            FilledButton.tonalIcon(
              icon: const Icon(Icons.add),
              label: const Text('添加字段'),
              onPressed: () => context.push(AppRouter.defineFieldPath),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // 使用ValueListenableBuilder来响应fieldsBox的变化
        ValueListenableBuilder(
          valueListenable: fieldsBox.listenable(),
          builder: (context, Box<TemplateField> box, _) {
            final fields = template.fieldIds
                .map((id) => box.get(id))
                .where((field) => field != null)
                .cast<TemplateField>()
                .toList();

            if (fields.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 24.0),
                child: Center(child: Text('请添加至少一个字段')),
              );
            }
            return Column(
              children: fields.map((field) => _FieldListItem(field: field)).toList(),
            );
          },
        ),
      ],
    );
  }
}

// 字段列表项UI组件
class _FieldListItem extends ConsumerWidget {
  final TemplateField field;
  const _FieldListItem({required this.field});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4.0),
      child: ListTile(
        leading: const Icon(Icons.crop),
        title: Text(field.name),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline),
          onPressed: () async {
            await ref.read(templateCreationProvider.notifier).removeField(field.id);
          },
        ),
        onTap: () {
          // 点击列表项，跳转到编辑页面，并将当前字段作为参数传递
          context.push(AppRouter.defineFieldPath, extra: field);
        },
      ),
    );
  }
}