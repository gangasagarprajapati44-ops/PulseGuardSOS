import 'package:hive_flutter/hive_flutter.dart';
import '../models/safety_ping.dart';

class OfflineVaultService {
  OfflineVaultService._();

  static const String _boxName = 'aegis_vault_box';
  static const String _senderIdKey = 'saved_my_sender_id';
  static const String _targetResponseIdKey = 'saved_target_response_id';

  static Future<void> init() async {
    await Hive.initFlutter();
    if (!Hive.isBoxOpen(_boxName)) {
      await Hive.openBox<dynamic>(_boxName);
    }
  }

  static Box<dynamic> get _box => Hive.box<dynamic>(_boxName);

  static Future<void> savePing(SafetyPing ping) async {
    final existing = getAllPings();
    existing.add(ping);
    await _box.put(
      'pings',
      existing.map((p) => p.toMap()).toList(),
    );
  }

  static List<SafetyPing> getAllPings() {
    if (!Hive.isBoxOpen(_boxName)) return [];
    final raw = _box.get('pings');
    if (raw is! List) return [];
    return raw
        .whereType()
        .map((m) => SafetyPing.fromMap(Map<String, dynamic>.from(m)))
        .toList();
  }

  static Future<void> saveIds({
    required String mySenderId,
    required String targetResponseId,
  }) async {
    if (!Hive.isBoxOpen(_boxName)) return;
    await _box.put(_senderIdKey, mySenderId.trim().toUpperCase());
    await _box.put(_targetResponseIdKey, targetResponseId.trim().toUpperCase());
  }

  static ({String mySenderId, String targetResponseId}) getSavedIds() {
    if (!Hive.isBoxOpen(_boxName)) {
      return (mySenderId: 'SENDER-1', targetResponseId: 'RESP-2');
    }
    final s = (_box.get(_senderIdKey) ?? 'SENDER-1').toString().trim().toUpperCase();
    final r =
        (_box.get(_targetResponseIdKey) ?? 'RESP-2').toString().trim().toUpperCase();
    return (
      mySenderId: s.isEmpty ? 'SENDER-1' : s,
      targetResponseId: r.isEmpty ? 'RESP-2' : r,
    );
  }
}
