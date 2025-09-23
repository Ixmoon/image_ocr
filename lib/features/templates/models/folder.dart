import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

part 'folder.g.dart';

@HiveType(typeId: 3) // 确保 typeId 是唯一的
class Folder extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  String name;

  // 用于支持文件夹嵌套，根目录的 parentId 为 null
  @HiveField(2)
  String? parentId;

  // 存储此文件夹内模板和子文件夹的ID列表，用于排序
  @HiveField(3)
  List<String> childrenIds;

  Folder({
    String? id,
    required this.name,
    this.parentId,
    List<String>? childrenIds,
  })  : id = id ?? const Uuid().v4(),
        childrenIds = childrenIds ?? [];

  Folder copyWith({
    String? id,
    String? name,
    String? parentId,
    List<String>? childrenIds,
    bool setParentIdToNull = false,
  }) {
    return Folder(
      id: id ?? this.id,
      name: name ?? this.name,
      parentId: setParentIdToNull ? null : (parentId ?? this.parentId),
      childrenIds: childrenIds ?? List<String>.from(this.childrenIds),
    );
  }
}