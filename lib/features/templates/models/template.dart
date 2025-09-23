import 'package:hive/hive.dart';

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

  @HiveField(4)
  String? folderId; // 模板所属的文件夹ID，为 null 表示在根目录

  Template({
    required this.id,
    required this.name,
    required this.sourceImagePath,
    required this.fieldIds,
    this.folderId,
  });

  Template copyWith({
    String? id,
    String? name,
    String? sourceImagePath,
    List<String>? fieldIds,
    String? folderId,
    bool setFolderIdToNull = false,
  }) {
    return Template(
      id: id ?? this.id,
      name: name ?? this.name,
      sourceImagePath: sourceImagePath ?? this.sourceImagePath,
      fieldIds: fieldIds ?? List<String>.from(this.fieldIds),
      folderId: setFolderIdToNull ? null : (folderId ?? this.folderId),
    );
  }
}