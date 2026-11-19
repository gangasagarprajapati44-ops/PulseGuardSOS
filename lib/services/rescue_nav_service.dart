import 'package:url_launcher/url_launcher.dart';

class RescueNavService {
  static Future<bool> navigateToTargetLocation(double lat, double lng) async {
    final Uri targetMapsUri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving',
    );
    try {
      return await launchUrl(
        targetMapsUri,
        mode: LaunchMode.platformDefault,
        webOnlyWindowName: '_blank',
      );
    } catch (_) {
      return false;
    }
  }
}
