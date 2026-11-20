import 'package:url_launcher/url_launcher.dart';

class EmergencyContact {
  final String name;
  final String phone;
  bool enabled;

  EmergencyContact({
    required this.name,
    required this.phone,
    this.enabled = true,
  });

  Map<String, dynamic> toMap() => {
        'name': name,
        'phone': phone,
        'enabled': enabled,
      };

  factory EmergencyContact.fromMap(Map<String, dynamic> map) {
    return EmergencyContact(
      name: (map['name'] ?? 'Contact').toString(),
      phone: (map['phone'] ?? '').toString(),
      enabled: map['enabled'] != false,
    );
  }
}

class EmergencyContactService {
  EmergencyContactService._();
  static final EmergencyContactService instance = EmergencyContactService._();

  String buildSosLocationMessage({
    required String senderId,
    required double lat,
    required double lng,
  }) {
    final mapsUrl = 'https://www.google.com/maps?q=$lat,$lng';
    return 'EMERGENCY SOS from $senderId! I need help. Live Location: $mapsUrl';
  }

  Future<bool> openSmsToContacts({
    required List<EmergencyContact> contacts,
    required String senderId,
    required double lat,
    required double lng,
  }) async {
    final phones = contacts
        .where((c) => c.enabled && c.phone.trim().isNotEmpty)
        .map((c) => c.phone.trim().replaceAll(RegExp(r'[^0-9+]'), ''))
        .where((p) => p.isNotEmpty)
        .toList();

    if (phones.isEmpty) return false;

    final body = buildSosLocationMessage(
      senderId: senderId,
      lat: lat,
      lng: lng,
    );
    final recipients = phones.join(',');
    final uri = Uri.parse(
      'sms:$recipients?body=${Uri.encodeComponent(body)}',
    );

    if (await canLaunchUrl(uri)) {
      return launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    return false;
  }
}
