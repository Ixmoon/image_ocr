import 'package:hive/hive.dart';
import 'package:image_clone_tool/features/templates/models/template_field.dart';

// 指示Hive代码生成器处理这个文件
part 'template.g.dart';

// 模板的整体数据模型
@HiveType(typeId: 1)
class Template extends HiveObject {
  @HiveField(0)
  final String id; // 模板的唯一ID

  @HiveField(1)
  String name; // 模板名称，用户可编辑

  @HiveField(2)
  final String sourceImagePath; // 源图片的本地路径

  @HiveField(3)
  // 存储关联的TemplateField的ID列表
  List<String> fieldIds;

  Template({
    required this.id,
    required this.name,
    required this.sourceImagePath,
    required this.fieldIds,
  });
}