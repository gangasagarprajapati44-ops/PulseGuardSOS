// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'safety_ping.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class SafetyPingAdapter extends TypeAdapter<SafetyPing> {
  @override
  final int typeId = 0;

  @override
  SafetyPing read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return SafetyPing(
      id: fields[0] as String,
      latitude: fields[1] as double,
      longitude: fields[2] as double,
      timestamp: fields[3] as DateTime,
      isSos: fields[4] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, SafetyPing obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.latitude)
      ..writeByte(2)
      ..write(obj.longitude)
      ..writeByte(3)
      ..write(obj.timestamp)
      ..writeByte(4)
      ..write(obj.isSos);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SafetyPingAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
