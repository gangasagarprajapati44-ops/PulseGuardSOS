import 'package:url_launcher/url_launcher.dart';

class RescueNavService {
  RescueNavService._();

  static Future<bool> navigateToTargetLocation(
    double destinationLat,
    double destinationLng, {
    double? originLat,
    double? originLng,
  }) async {
    final String dest = '$destinationLat,$destinationLng';
    final String urlStr = (originLat != null && originLng != null)
        ? 'https://www.google.com/maps/dir/?api=1&origin=$originLat,$originLng&destination=$dest&travelmode=driving'
        : 'https://www.google.com/maps/dir/?api=1&destination=$dest&travelmode=driving';

    final uri = Uri.parse(urlStr);
    if (await canLaunchUrl(uri)) {
      return launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    return false;
  }
}
