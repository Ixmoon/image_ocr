import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:image_clone_tool/features/templates/models/template.dart';

// 模板本地存储服务，封装Hive操作
class TemplateService {
  // Hive Box的名称，作为数据表的唯一标识
  static const String _boxName = 'templates';

  // 获取Hive Box实例，如果未打开则会先打开
  Future<Box<Template>> _getBox() async {
    return await Hive.openBox<Template>(_boxName);
  }

  // 获取所有模板
  Future<List<Template>> getTemplates() async {
    final box = await _getBox();
    return box.values.toList();
  }

  // 保存或更新一个模板
  Future<void> saveTemplate(Template template) async {
    final box = await _getBox();
    // Hive使用key来区分条目，这里我们用模板的id作为key
    await box.put(template.id, template);
  }

  // 根据ID删除一个模板
  Future<void> deleteTemplate(String id) async {
    final box = await _getBox();
    await box.delete(id);
  }
}

// 创建Provider，以便在应用中方便地访问TemplateService
final templateServiceProvider = Provider<TemplateService>((ref) {
  return TemplateService();
});