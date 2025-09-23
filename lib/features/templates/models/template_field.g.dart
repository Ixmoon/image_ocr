// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'template_field.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class TemplateFieldAdapter extends TypeAdapter<TemplateField> {
  @override
  final int typeId = 2;

  @override
  TemplateField read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return TemplateField(
      id: fields[0] as String,
      name: fields[1] as String,
      labelRect: fields[2] as Rect,
      valueRect: fields[3] as Rect,
      valueImageBytes: (fields[4] as List).cast<int>(),
    );
  }

  @override
  void write(BinaryWriter writer, TemplateField obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.labelRect)
      ..writeByte(3)
      ..write(obj.valueRect)
      ..writeByte(4)
      ..write(obj.valueImageBytes);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TemplateFieldAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class RectAdapterAdapter extends TypeAdapter<RectAdapter> {
  @override
  final int typeId = 3;

  @override
  RectAdapter read(BinaryReader reader) {
    return RectAdapter();
  }

  @override
  void write(BinaryWriter writer, RectAdapter obj) {
    writer.writeByte(0);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RectAdapterAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
