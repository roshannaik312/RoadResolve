import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

class PlaceInfo {
  const PlaceInfo({this.road, this.locality, this.county});
  final String? road;
  final String? locality;

  /// e.g. "Wake County" (iOS reports it as the sub-administrative area).
  final String? county;
}

class LocationService {
  const LocationService._();

  /// Fast fix for tagging a report: use a recent stream position if we
  /// have one, otherwise ask for a fresh one (with a short timeout).
  static Future<Position?> currentPosition({Position? recent}) async {
    if (recent != null &&
        DateTime.now().difference(recent.timestamp).inSeconds.abs() < 15) {
      return recent;
    }
    try {
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return recent;
      }
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      );
    } catch (_) {
      try {
        return await Geolocator.getLastKnownPosition() ?? recent;
      } catch (_) {
        return recent;
      }
    }
  }

  static Future<PlaceInfo> describe(double lat, double lng) async {
    try {
      final marks = await placemarkFromCoordinates(
        lat,
        lng,
      ).timeout(const Duration(seconds: 6));
      if (marks.isEmpty) return const PlaceInfo();
      final p = marks.first;
      String? road;
      for (final s in [p.thoroughfare, p.street, p.name]) {
        if (s != null && s.trim().isNotEmpty) {
          road = s.trim();
          break;
        }
      }
      return PlaceInfo(
        road: road,
        locality: p.locality ?? p.subAdministrativeArea,
        county: p.subAdministrativeArea,
      );
    } catch (_) {
      return const PlaceInfo();
    }
  }
}
