import 'package:geolocator/geolocator.dart';

class LocationUnavailable implements Exception {
  LocationUnavailable(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Current device position, asking for permission if needed.
Future<Position> determinePosition() async {
  if (!await Geolocator.isLocationServiceEnabled()) {
    throw LocationUnavailable('Location services are turned off.');
  }
  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  switch (permission) {
    case LocationPermission.denied:
      throw LocationUnavailable('Location permission was denied.');
    case LocationPermission.deniedForever:
      throw LocationUnavailable(
        'Location permission is blocked. Enable it in system settings.',
      );
    case LocationPermission.whileInUse:
    case LocationPermission.always:
    case LocationPermission.unableToDetermine:
      return Geolocator.getCurrentPosition();
  }
}
