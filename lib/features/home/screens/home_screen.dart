import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_clone_tool/core/router/app_router.dart';
import 'package:image_clone_tool/features/templates/models/template.dart';
import 'package:image_clone_tool/features/templates/providers/template_providers.dart';

// 主屏幕，模板列表和管理中心
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final templatesAsyncValue = ref.watch(templatesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('我的模板'),
      ),
      body: templatesAsyncValue.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(
          child: Text('加载模板失败: $err'),
        ),
        data: (templates) => templates.isEmpty
            ? const _EmptyState()
            : RefreshIndicator(
                // 修复：直接refresh provider即可，无需访问.future
                onRefresh: () async => ref.invalidate(templatesProvider),
                child: ListView.builder(
                  padding: const EdgeInsets.all(8.0),
                  itemCount: templates.length,
                  itemBuilder: (context, index) {
                    return _TemplateListItem(template: templates[index]);
                  },
                ),
              ),
      ),
      // 使用FloatingActionButton作为创建新模板的主要入口，更符合Material Design规范
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          ref.read(templateCreationProvider.notifier).createNew();
          context.push(AppRouter.createTemplatePath);
        },
        icon: const Icon(Icons.add),
        label: const Text('创建模板'),
      ),
    );
  }
}

// 空状态UI组件，当没有模板时显示
class _EmptyState extends ConsumerWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.style_outlined,
            size: 80,
            color: theme.colorScheme.secondary,
          ),
          const SizedBox(height: 16),
          Text(
            '还没有模板',
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            '创建一个模板来开始批量替换图片吧！',
            style: theme.textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('立即创建'),
            onPressed: () {
              ref.read(templateCreationProvider.notifier).createNew();
              context.push(AppRouter.createTemplatePath);
            },
          )
        ],
      ),
    );
  }
}

// 模板列表项UI组件
class _TemplateListItem extends ConsumerWidget {
  final Template template;
  const _TemplateListItem({required this.template});

  // 显示删除确认对话框
  Future<void> _showDeleteConfirmation(BuildContext context, WidgetRef ref) async {
    final bool? confirmed = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('您确定要删除模板 "${template.name}" 吗？此操作无法撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(templatesProvider.notifier).deleteTemplate(template.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('模板 "${template.name}" 已删除')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6.0),
      child: InkWell(
        onTap: () => context.push(AppRouter.applyTemplatePath, extra: template),
        borderRadius: BorderRadius.circular(12.0),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
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
                    Text(
                      '包含 ${template.fieldIds.length} 个字段',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              // 编辑按钮
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                tooltip: '编辑',
                onPressed: () {
                  ref.read(templateCreationProvider.notifier).loadForEditing(template);
                  context.push('${AppRouter.createTemplatePath}/${template.id}');
                },
              ),
              // 删除按钮
              IconButton(
                icon: Icon(Icons.delete_outline, color: theme.colorScheme.error),
                tooltip: '删除',
                onPressed: () => _showDeleteConfirmation(context, ref),
              ),
            ],
          ),
        ),
      ),
    );
  }
}