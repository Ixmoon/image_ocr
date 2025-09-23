import 'dart:ui';

import 'package:hive/hive.dart';

class RectAdapter extends TypeAdapter<Rect> {
  @override
  final int typeId = 100; // Assign a unique typeId

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