import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:image_clone_tool/features/templates/models/template.dart';
import 'package:image_clone_tool/features/templates/models/template_field.dart';
import 'package:image_clone_tool/features/templates/services/template_service.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

part 'template_providers.g.dart';

// --- 模板列表 Provider ---
@Riverpod(keepAlive: true)
class Templates extends AsyncNotifier<List<Template>> {
  @override
  Future<List<Template>> build() async {
    // build方法负责提供初始状态
    return _fetchTemplates();
  }

  // 从依赖的服务中获取模板列表
  Future<List<Template>> _fetchTemplates() async {
    return await ref.read(templateServiceProvider).getTemplates();
  }

  // 添加或更新模板
  Future<void> saveTemplate(Template template) async {
    // 设置为加载状态，然后执行操作
    state = const AsyncValue.loading();
    // 使用guard可以优雅地处理错误
    state = await AsyncValue.guard(() async {
      await ref.read(templateServiceProvider).saveTemplate(template);
      return _fetchTemplates(); // 重新获取列表以更新UI
    });
  }

  // 删除模板
  Future<void> deleteTemplate(String id) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await ref.read(templateServiceProvider).deleteTemplate(id);
      return _fetchTemplates(); // 重新获取列表
    });
  }
}


// --- 模板创建/编辑状态 Provider (大幅修改) ---
@riverpod
class TemplateCreation extends AutoDisposeNotifier<Template?> {
  // 获取两个 Box 的引用
  late final Box<Template> _templatesBox;
  late final Box<TemplateField> _fieldsBox;

  @override
  Template? build() {
    // 在 build 方法中初始化 Box 引用
    _templatesBox = Hive.box<Template>('templates');
    _fieldsBox = Hive.box<TemplateField>('template_fields');
    return null;
  }

  // 开始创建一个新模板
  void createNew() {
    state = null;
  }

  // 加载一个已有的模板进行编辑
  void loadForEditing(Template template) {
    state = template;
  }

  // 设置源图片，这是创建模板的第一步
  void setSourceImage(String imagePath) {
    final newTemplate = Template(
      id: state?.id ?? const Uuid().v4(),
      name: state?.name ?? '新模板',
      sourceImagePath: imagePath,
      fieldIds: state?.fieldIds ?? [], // 初始化为空列表
    );
    state = newTemplate;
  }

  // 更新模板名称
  void updateName(String newName) {
    if (state != null) {
      state!.name = newName;
      // 创建一个新实例来触发UI更新
      state = Template(
        id: state!.id,
        name: state!.name,
        sourceImagePath: state!.sourceImagePath,
        fieldIds: state!.fieldIds,
      );
    }
  }

  // 添加或更新一个字段
  Future<void> addOrUpdateField(TemplateField field) async {
    if (state == null) {
      //print('[ERROR] TemplateCreation Provider: State is null, cannot add field.');
      return;
    }

    try {
      // 1. 将 TemplateField 对象存入它自己的 Box
      //print('[DEBUG] TemplateCreation Provider: Putting field into _fieldsBox...');
      await _fieldsBox.put(field.id, field);
      //print('[DEBUG] TemplateCreation Provider: Field put successful.');

      // 2. 将这个字段的ID关联到 Template 的 fieldIds 列表中
      final fieldIds = List<String>.from(state!.fieldIds);
      if (!fieldIds.contains(field.id)) {
        //print('[DEBUG] TemplateCreation Provider: Adding new field ID to list.');
        fieldIds.add(field.id);
      } else {
        //print('[DEBUG] TemplateCreation Provider: Field ID already in list.');
      }
      
      // 触发状态更新
      state = Template(
          id: state!.id,
          name: state!.name,
          sourceImagePath: state!.sourceImagePath,
          fieldIds: fieldIds,
        );
      //print('[DEBUG] TemplateCreation Provider: State updated successfully.');
    } catch (e) {
      //print('[ERROR] TemplateCreation Provider: addOrUpdateField failed with exception: $e');
      rethrow;
    }
  }
  
  // 删除一个字段
  Future<void> removeField(String fieldId) async {
    if (state == null) return;

    // 1. 从 TemplateField 的 Box 中删除该对象本身
    await _fieldsBox.delete(fieldId);

    // 2. 从 Template 的 fieldIds 列表中移除关联
    final fieldIds = List<String>.from(state!.fieldIds);
    fieldIds.remove(fieldId);
    
    // 触发状态更新
    state = Template(
        id: state!.id,
        name: state!.name,
        sourceImagePath: state!.sourceImagePath,
        fieldIds: fieldIds,
      );
  }

  // 保存当前正在创建/编辑的模板到持久化存储
  Future<void> save() async {
    if (state != null) {
      await ref.read(templatesProvider.notifier).saveTemplate(state!);
    }
  }
}