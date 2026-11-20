import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class LiveSosAlert {
  final String id;
  final String senderId;
  final String targetResponseId;
  final double latitude;
  final double longitude;
  final DateTime timestamp;
  final bool isVerifiedPair;

  LiveSosAlert({
    required this.id,
    required this.senderId,
    required this.targetResponseId,
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    required this.isVerifiedPair,
  });

  static String _sanitizeId(String raw, String fallback) {
    final cleaned = raw
        .trim()
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9_-]'), '');
    if (cleaned.isEmpty) return fallback;
    return cleaned.length > 24 ? cleaned.substring(0, 24) : cleaned;
  }

  static String _obfuscateCoords({
    required double lat,
    required double lng,
    required String pairSecret,
  }) {
    final plain = jsonEncode({'lat': lat, 'lng': lng});
    final plainBytes = utf8.encode(plain);
    final keyBytes = utf8.encode(pairSecret);
    final cipherBytes = <int>[];

    for (var i = 0; i < plainBytes.length; i++) {
      cipherBytes.add(plainBytes[i] ^ keyBytes[i % keyBytes.length]);
    }
    return base64Encode(cipherBytes);
  }

  static ({double lat, double lng})? _deobfuscateCoords({
    required String cipherBase64,
    required String pairSecret,
  }) {
    try {
      final cipherBytes = base64Decode(cipherBase64);
      final keyBytes = utf8.encode(pairSecret);
      final plainBytes = <int>[];

      for (var i = 0; i < cipherBytes.length; i++) {
        plainBytes.add(cipherBytes[i] ^ keyBytes[i % keyBytes.length]);
      }

      final decoded = jsonDecode(utf8.decode(plainBytes));
      if (decoded is! Map) return null;

      final lat = (decoded['lat'] as num?)?.toDouble();
      final lng = (decoded['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) return null;
      if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return null;

      return (lat: lat, lng: lng);
    } catch (_) {
      return null;
    }
  }

  factory LiveSosAlert.fromDoc(
    DocumentSnapshot doc, {
    required String expectedPairSecret,
  }) {
    final rawData = doc.data();
    final data =
        rawData is Map<String, dynamic> ? rawData : <String, dynamic>{};
    final ts = data['timestamp'];
    final alertTime = ts is Timestamp ? ts.toDate() : DateTime.now();

    final sender = _sanitizeId(
      (data['senderId'] ?? 'UNKNOWN').toString(),
      'UNKNOWN',
    );
    final target = _sanitizeId(
      (data['targetResponseId'] ?? 'RESP-2').toString(),
      'RESP-2',
    );

    final encCoords = (data['encCoords'] ?? '').toString();
    final decrypted = _deobfuscateCoords(
      cipherBase64: encCoords,
      pairSecret: expectedPairSecret,
    );

    if (decrypted != null) {
      return LiveSosAlert(
        id: doc.id,
        senderId: sender,
        targetResponseId: target,
        latitude: decrypted.lat,
        longitude: decrypted.lng,
        timestamp: alertTime,
        isVerifiedPair: true,
      );
    }

    // Fallback only if legacy unencrypted doc was written during testing
    final fallbackLat = ((data['latitude'] ?? 0) as num).toDouble();
    final fallbackLng = ((data['longitude'] ?? 0) as num).toDouble();
    return LiveSosAlert(
      id: doc.id,
      senderId: sender,
      targetResponseId: target,
      latitude: fallbackLat,
      longitude: fallbackLng,
      timestamp: alertTime,
      isVerifiedPair: false,
    );
  }
}

class SosCloudService {
  SosCloudService._();
  static final SosCloudService instance = SosCloudService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Future<String> _ensureAuthenticatedUid() async {
    final current = _auth.currentUser;
    if (current != null) return current.uid;
    final cred = await _auth.signInAnonymously();
    return cred.user?.uid ?? 'anon_user';
  }

  String buildPairSecret({
    required String senderId,
    required String targetResponseId,
  }) {
    final s = LiveSosAlert._sanitizeId(senderId, 'SENDER-1');
    final r = LiveSosAlert._sanitizeId(targetResponseId, 'RESP-2');
    return 'AEGIS_SEC::$s::$r';
  }

  Future<void> sendSosToTarget({
    required String senderId,
    required String targetResponseId,
    required double latitude,
    required double longitude,
  }) async {
    final uid = await _ensureAuthenticatedUid();
    final cleanSender = LiveSosAlert._sanitizeId(senderId, 'SENDER-1');
    final cleanTarget =
        LiveSosAlert._sanitizeId(targetResponseId, 'RESP-2');
    final pairSecret = buildPairSecret(
      senderId: cleanSender,
      targetResponseId: cleanTarget,
    );

    final encCoords = LiveSosAlert._obfuscateCoords(
      lat: latitude,
      lng: longitude,
      pairSecret: pairSecret,
    );

    await _db.collection('sos_alerts').add({
      'ownerUid': uid,
      'senderId': cleanSender,
      'targetResponseId': cleanTarget,
      'encCoords': encCoords,
      'status': 'ACTIVE_SOS',
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  Stream<LiveSosAlert?> watchIncomingAlert({
    required String myListenId,
    required String mySenderId,
  }) async* {
    await _ensureAuthenticatedUid();

    final cleanListen = LiveSosAlert._sanitizeId(myListenId, 'SENDER-1');
    final cleanSender = LiveSosAlert._sanitizeId(mySenderId, 'SENDER-1');

    yield* _db
        .collection('sos_alerts')
        .where('targetResponseId', isEqualTo: cleanListen)
        .snapshots()
        .map((snapshot) {
      if (snapshot.docs.isEmpty) return null;
      final cutoff = DateTime.now().subtract(const Duration(minutes: 2));

      final recentAlerts = <LiveSosAlert>[];
      for (final d in snapshot.docs) {
        final raw = d.data();
        final sender = LiveSosAlert._sanitizeId(
          (raw['senderId'] ?? 'UNKNOWN').toString(),
          'UNKNOWN',
        );
        if (sender == cleanSender) continue;

        final pairSecret = buildPairSecret(
          senderId: sender,
          targetResponseId: cleanListen,
        );
        final alert = LiveSosAlert.fromDoc(d, expectedPairSecret: pairSecret);

        if (alert.isVerifiedPair && alert.timestamp.isAfter(cutoff)) {
          recentAlerts.add(alert);
        }
      }

      if (recentAlerts.isEmpty) return null;
      recentAlerts.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return recentAlerts.first;
    });
  }
}
