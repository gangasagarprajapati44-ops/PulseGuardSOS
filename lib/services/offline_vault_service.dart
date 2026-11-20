import 'package:hive_flutter/hive_flutter.dart';
import '../models/safety_ping.dart';

class OfflineVaultService {
  OfflineVaultService._();

  static const String _pingsBoxName = 'safety_pings_box';
  static const String _configBoxName = 'aegis_config_box';
  static const String _senderIdKey = 'saved_my_sender_id';
  static const String _targetResponseIdKey = 'saved_target_response_id';
  static const String _handledAlertsKey = 'handled_alert_ids';

  static Future<void> init() async {
    await Hive.initFlutter();
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(SafetyPingAdapter());
    }
    if (!Hive.isBoxOpen(_pingsBoxName)) {
      await Hive.openBox<SafetyPing>(_pingsBoxName);
    }
    if (!Hive.isBoxOpen(_configBoxName)) {
      await Hive.openBox<dynamic>(_configBoxName);
    }
  }

  static Box<SafetyPing> get _pingsBox => Hive.box<SafetyPing>(_pingsBoxName);
  static Box<dynamic> get _configBox => Hive.box<dynamic>(_configBoxName);

  static Future<void> savePing(SafetyPing ping) async {
    if (!Hive.isBoxOpen(_pingsBoxName)) return;
    await _pingsBox.add(ping);
  }

  static List<SafetyPing> getAllPings() {
    if (!Hive.isBoxOpen(_pingsBoxName)) return [];
    return _pingsBox.values.toList();
  }

  static Future<void> saveIds({
    required String mySenderId,
    required String targetResponseId,
  }) async {
    if (!Hive.isBoxOpen(_configBoxName)) return;
    await _configBox.put(_senderIdKey, mySenderId.trim().toUpperCase());
    await _configBox.put(
      _targetResponseIdKey,
      targetResponseId.trim().toUpperCase(),
    );
  }

  static ({String mySenderId, String targetResponseId}) getSavedIds() {
    if (!Hive.isBoxOpen(_configBoxName)) {
      return (mySenderId: 'SENDER-1', targetResponseId: 'RESP-2');
    }
    final s = (_configBox.get(_senderIdKey) ?? 'SENDER-1')
        .toString()
        .trim()
        .toUpperCase();
    final r = (_configBox.get(_targetResponseIdKey) ?? 'RESP-2')
        .toString()
        .trim()
        .toUpperCase();
    return (
      mySenderId: s.isEmpty ? 'SENDER-1' : s,
      targetResponseId: r.isEmpty ? 'RESP-2' : r,
    );
  }

  static Set<String> getHandledAlertIds() {
    if (!Hive.isBoxOpen(_configBoxName)) return <String>{};
    final raw = _configBox.get(_handledAlertsKey);
    if (raw is! List) return <String>{};
    return raw.map((e) => e.toString()).toSet();
  }

  static Future<void> markAlertHandled(String alertId) async {
    if (!Hive.isBoxOpen(_configBoxName) || alertId.trim().isEmpty) return;
    final current = getHandledAlertIds().toList();
    if (!current.contains(alertId)) {
      current.add(alertId);
      final trimmed = current.length > 100
          ? current.sublist(current.length - 100)
          : current;
      await _configBox.put(_handledAlertsKey, trimmed);
    }
  }
}
