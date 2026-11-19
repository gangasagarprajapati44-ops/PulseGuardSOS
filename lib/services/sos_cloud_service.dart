import 'package:cloud_firestore/cloud_firestore.dart';

class LiveSosAlert {
  final String id;
  final String senderId;
  final String targetResponseId;
  final double latitude;
  final double longitude;
  final DateTime timestamp;

  LiveSosAlert({
    required this.id,
    required this.senderId,
    required this.targetResponseId,
    required this.latitude,
    required this.longitude,
    required this.timestamp,
  });

  factory LiveSosAlert.fromDoc(DocumentSnapshot doc) {
    final rawData = doc.data();
    final data =
        rawData is Map<String, dynamic> ? rawData : <String, dynamic>{};
    final ts = data['timestamp'];
    return LiveSosAlert(
      id: doc.id,
      senderId: (data['senderId'] ?? 'UNKNOWN').toString().toUpperCase(),
      targetResponseId:
          (data['targetResponseId'] ?? 'RESP-2').toString().toUpperCase(),
      latitude: ((data['latitude'] ?? 0) as num).toDouble(),
      longitude: ((data['longitude'] ?? 0) as num).toDouble(),
      timestamp: ts is Timestamp ? ts.toDate() : DateTime.now(),
    );
  }
}

class SosCloudService {
  SosCloudService._();
  static final SosCloudService instance = SosCloudService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<void> sendSosToTarget({
    required String senderId,
    required String targetResponseId,
    required double latitude,
    required double longitude,
  }) async {
    final cleanSender = senderId.trim().toUpperCase();
    final cleanTarget = targetResponseId.trim().toUpperCase();

    await _db.collection('sos_alerts').add({
      'senderId': cleanSender.isEmpty ? 'SENDER-1' : cleanSender,
      'targetResponseId': cleanTarget.isEmpty ? 'RESP-2' : cleanTarget,
      'latitude': latitude,
      'longitude': longitude,
      'status': 'ACTIVE_SOS',
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  // Listens for SOS alerts directed to this device's own ID (when acting as responder)
  // while strictly ignoring alerts sent by this device's own senderId.
  Stream<LiveSosAlert?> watchIncomingAlert({
    required String myListenId,
    required String mySenderId,
  }) {
    final cleanListen = myListenId.trim().toUpperCase();
    final cleanSender = mySenderId.trim().toUpperCase();

    return _db
        .collection('sos_alerts')
        .where('targetResponseId', isEqualTo: cleanListen)
        .snapshots()
        .map((snapshot) {
      if (snapshot.docs.isEmpty) return null;
      final alerts = snapshot.docs
          .map((d) => LiveSosAlert.fromDoc(d))
          .where((a) => a.senderId.trim().toUpperCase() != cleanSender)
          .toList();
      if (incomingEmpty(alerts)) return null;
      alerts.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return alerts.first;
    });
  }

  bool incomingEmpty(List<LiveSosAlert> list) => list.isEmpty;
}
