import 'package:hive/hive.dart';

part 'safety_ping.g.dart';

@HiveType(typeId: 0)
class SafetyPing extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final double latitude;

  @HiveField(2)
  final double longitude;

  @HiveField(3)
  final DateTime timestamp;

  @HiveField(4)
  final bool isSos;

  SafetyPing({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    this.isSos = false,
  });
}
