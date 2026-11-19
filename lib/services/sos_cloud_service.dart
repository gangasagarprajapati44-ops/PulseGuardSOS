import 'package:cloud_firestore/cloud_firestore.dart';

class LiveSosAlert {
  final String id;
  final String targetId;
  final String groupName;
  final double latitude;
  final double longitude;
  final DateTime timestamp;

  LiveSosAlert({
    required this.id,
    required this.targetId,
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
      targetId: (data['targetId'] ?? 'AEGIS-1001').toString().toUpperCase(),
      groupName: (data['groupName'] ?? 'EMERGENCY GROUP').toString(),
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
    required String targetId,
    required String groupName,
    required double latitude,
    required double longitude,
  }) async {
    final cleanId = targetId.trim().toUpperCase();
    await _db.collection('sos_alerts').add({
      'targetId': cleanId.isEmpty ? 'AEGIS-1001' : cleanId,
      'groupName': groupName,
      'latitude': latitude,
      'longitude': longitude,
      'status': 'ACTIVE_SOS',
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  Stream<LiveSosAlert?> watchLatestAlertForId(String watchId) {
    final normalizedWatchId = watchId.trim().toUpperCase();
    return _db
        .collection('sos_alerts')
        .where('targetId', isEqualTo: normalizedWatchId)
        .snapshots()
        .map((snapshot) {
      if (snapshot.docs.isEmpty) return null;
      final alerts = snapshot.docs.map((d) => LiveSosAlert.fromDoc(d)).toList();
      alerts.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return alerts.first;
    });
  }
}
