import 'package:hive/hive.dart';

part 'template_field.g.dart';

/// 模板中单个字段的数据模型。
///
/// 它只存储一个信息：字段的名称（例如“姓名”），这个名称将作为后续
/// OCR流程中用于定位的“锚点文本”。
@HiveType(typeId: 2)
class TemplateField extends HiveObject {
  @HiveField(0)
  final String id; // 唯一ID

  @HiveField(1)
  final String name; // 字段名，如 "姓名", 用作锚点

  TemplateField({
    required this.id,
    required this.name,
  });
}