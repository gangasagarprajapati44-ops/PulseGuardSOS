import 'package:cloud_firestore/cloud_firestore.dart';

class LiveSosAlert {
  final String id;
  final String senderId;
  final String responseId;
  final String groupName;
  final double latitude;
  final double longitude;
  final DateTime timestamp;

  LiveSosAlert({
    required this.id,
    required this.senderId,
    required this.responseId,
    required this.groupName,
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
      senderId: (data['senderId'] ?? 'UNKNOWN-SENDER').toString().toUpperCase(),
      responseId:
          (data['responseId'] ?? 'RESP-1001').toString().toUpperCase(),
      groupName: (data['groupName'] ?? 'RESPONSE GROUP').toString(),
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

  Future<void> publishSosAlert({
    required String senderId,
    required String responseId,
    required String groupName,
    required double latitude,
    required double longitude,
  }) async {
    final cleanSender = senderId.trim().toUpperCase();
    final cleanResponse = responseId.trim().toUpperCase();
    await _db.collection('sos_alerts').add({
      'senderId': cleanSender.isEmpty ? 'SENDER-1' : cleanSender,
      'responseId': cleanResponse.isEmpty ? 'RESP-1' : cleanResponse,
      'groupName': groupName,
      'latitude': latitude,
      'longitude': longitude,
      'status': 'ACTIVE_SOS',
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  Future<void> publishSosToResponseIds({
    required String senderId,
    required List<String> responseIds,
    required String groupName,
    required double latitude,
    required double longitude,
  }) async {
    final uniqueIds = responseIds
        .map((e) => e.trim().toUpperCase())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();

    for (final rId in uniqueIds) {
      await publishSosAlert(
        senderId: senderId,
        responseId: rId,
        groupName: groupName,
        latitude: latitude,
        longitude: longitude,
      );
    }
  }

  Stream<LiveSosAlert?> watchIncomingAlertForMyResponseId(
    String myResponseId,
    String mySenderId,
  ) {
    final cleanResp = myResponseId.trim().toUpperCase();
    final cleanSender = mySenderId.trim().toUpperCase();

    return _db
        .collection('sos_alerts')
        .where('responseId', isEqualTo: cleanResp)
        .snapshots()
        .map((snapshot) {
      if (snapshot.docs.isEmpty) return null;
      final incoming = snapshot.docs
          .map((d) => LiveSosAlert.fromDoc(d))
          .where((a) => a.senderId.trim().toUpperCase() != cleanSender)
          .toList();
      if (incoming.isEmpty) return null;
      incoming.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return incoming.first;
    });
  }
}
