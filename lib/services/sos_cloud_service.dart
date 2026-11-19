import 'package:cloud_firestore/cloud_firestore.dart';

class LiveSosAlert {
  final String id;
  final String groupName;
  final double latitude;
  final double longitude;
  final DateTime timestamp;

  LiveSosAlert({
    required this.id,
    required this.groupName,
    required this.latitude,
    required this.longitude,
    required this.timestamp,
  });

  factory LiveSosAlert.fromDoc(DocumentSnapshot doc) {
    final rawData = doc.data();
    final data = rawData is Map<String, dynamic> ? rawData : <String, dynamic>{};
    final ts = data['timestamp'];
    return LiveSosAlert(
      id: doc.id,
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
    required String groupName,
    required double latitude,
    required double longitude,
  }) async {
    await _db.collection('sos_alerts').add({
      'groupName': groupName,
      'latitude': latitude,
      'longitude': longitude,
      'status': 'ACTIVE_SOS',
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  Stream<LiveSosAlert?> watchLatestAlert() {
    return _db
        .collection('sos_alerts')
        .orderBy('timestamp', descending: true)
        .limit(1)
        .snapshots()
        .map((snapshot) {
      if (snapshot.docs.isEmpty) return null;
      return LiveSosAlert.fromDoc(snapshot.docs.first);
    });
  }
}
