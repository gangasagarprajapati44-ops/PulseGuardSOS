import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/safety_ping.dart';

class OfflineVaultService {
  static const String _boxName = 'aegis_safety_vault';
  static Box<SafetyPing>? _box;
  static final List<SafetyPing> _memoryFallback = [];

  static Future<void> init() async {
    try {
      await Hive.initFlutter();
      if (!Hive.isAdapterRegistered(0)) {
        Hive.registerAdapter(SafetyPingAdapter());
      }
      _box = await Hive.openBox<SafetyPing>(_boxName);
    } catch (e) {
      debugPrint('Vault fallback mode active: $e');
    }
  }

  static Future<void> savePing(SafetyPing ping) async {
    if (_box != null && _box!.isOpen) {
      await _box!.put(ping.id, ping);
    } else {
      _memoryFallback.add(ping);
    }
  }

  static List<SafetyPing> getAllPings() {
    if (_box != null && _box!.isOpen) {
      return _box!.values.toList();
    }
    return List.unmodifiable(_memoryFallback);
  }
}
