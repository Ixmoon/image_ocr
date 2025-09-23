import 'package:flutter/painting.dart';
import 'package:hive/hive.dart';

// 指示Hive代码生成器处理这个文件
part 'template_field.g.dart';

// 模板中单个字段的数据模型
@HiveType(typeId: 2)
class TemplateField extends HiveObject {
  @HiveField(0)
  final String id; // 唯一ID

  @HiveField(1)
  final String name; // 字段名，如 "姓名"

  @HiveField(2)
  final Rect labelRect; // 字段标签在源图片上的位置和大小

  @HiveField(3)
  final Rect valueRect; // 字段值在源图片上的位置和大小

  @HiveField(4)
  final List<int> valueImageBytes; // 裁剪下来的字段值图像块 (PNG格式)

  TemplateField({
    required this.id,
    required this.name,
    required this.labelRect,
    required this.valueRect,
    required this.valueImageBytes,
  });
}

// Rect不是Hive原生支持的类型，需要为其创建一个Adapter
@HiveType(typeId: 3)
class RectAdapter extends TypeAdapter<Rect> {
  @override
  final int typeId = 3;

  @override
  Rect read(BinaryReader reader) {
    final left = reader.readDouble();
    final top = reader.readDouble();
    final right = reader.readDouble();
    final bottom = reader.readDouble();
    return Rect.fromLTRB(left, top, right, bottom);
  }

  @override
  void write(BinaryWriter writer, Rect obj) {
    writer.writeDouble(obj.left);
    writer.writeDouble(obj.top);
    writer.writeDouble(obj.right);
    writer.writeDouble(obj.bottom);
  }
}