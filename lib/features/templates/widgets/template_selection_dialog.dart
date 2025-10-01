import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_ocr/features/templates/models/template.dart';
import 'package:image_ocr/features/templates/widgets/template_selector.dart';

/// 一个可导航、可复用的模板选择对话框（多选模式）。
class TemplateSelectionDialog extends ConsumerStatefulWidget {
  /// 已经从外部选择的模板ID集合，这些模板将在对话框中被禁用。
  final Set<String> alreadySelectedIds;

  const TemplateSelectionDialog({
    super.key,
    this.alreadySelectedIds = const {},
  });

  @override
  ConsumerState<TemplateSelectionDialog> createState() => _TemplateSelectionDialogState();
}

class _TemplateSelectionDialogState extends ConsumerState<TemplateSelectionDialog> {
  // 用于存储对话框内部的选择状态
  final Set<Template> _selectedTemplatesInDialog = {};

  void _onTemplateSelectionChanged(Template template) {
    setState(() {
      if (_selectedTemplatesInDialog.any((t) => t.id == template.id)) {
        _selectedTemplatesInDialog.removeWhere((t) => t.id == template.id);
      } else {
        _selectedTemplatesInDialog.add(template);
      }
    });
  }

  void _confirmSelection() {
    context.pop(_selectedTemplatesInDialog.toList());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('选择模板'),
      contentPadding: const EdgeInsets.fromLTRB(0, 20, 0, 24),
      content: SizedBox(
        width: double.maxFinite,
        child: TemplateSelector(
          selectedTemplates: _selectedTemplatesInDialog,
          alreadySelectedIds: widget.alreadySelectedIds,
          onTemplateSelectionChanged: _onTemplateSelectionChanged,
        ),
      ),
      actions: [
        TextButton(onPressed: () => context.pop(), child: const Text('取消')),
        FilledButton(
          onPressed: _confirmSelection,
          child: const Text('确认添加'),
        ),
      ],
    );
  }
}