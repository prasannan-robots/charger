import 'dart:math';

import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'google_api.dart';

/// Looks up charging stations near a point, nearest first.
typedef ChargerFinder = Future<List<ChargingStation>> Function(LatLng at);

class NoChargerInRangeException implements Exception {
  NoChargerInRangeException(this.stopsSoFar);
  final int stopsSoFar;

  @override
  String toString() => stopsSoFar == 0
      ? 'No charging station is reachable with the current battery. '
          'Try a higher battery level or range.'
      : 'Could not find a charging station after stop $stopsSoFar. '
          'Try a higher vehicle range.';
}

/// Usable range in km for a battery at [batteryPercent] of a car that does
/// [fullRangeKm] on a full charge.
double estimateRange(double batteryPercent, double fullRangeKm) =>
    (batteryPercent.clamp(0, 100) / 100) * fullRangeKm;

/// Great-circle (haversine) distance between two points in km.
double distanceKm(LatLng a, LatLng b) {
  const earthRadiusKm = 6371.0;
  double rad(double deg) => deg * pi / 180;
  final dLat = rad(b.latitude - a.latitude);
  final dLng = rad(b.longitude - a.longitude);
  final h = pow(sin(dLat / 2), 2) +
      cos(rad(a.latitude)) * cos(rad(b.latitude)) * pow(sin(dLng / 2), 2);
  return 2 * earthRadiusKm * asin(sqrt(h));
}

/// Picks charging stops along [route].
///
/// Drives along the route until the battery would drop to the reserve, then
/// searches backwards from that point (every [searchStepKm], never past the
/// previous stop) for the nearest charger. After a stop the car is assumed to
/// leave with [rangeAfterChargeKm] of range.
Future<List<ChargingStation>> planChargingStops({
  required List<LatLng> route,
  required double initialRangeKm,
  required double rangeAfterChargeKm,
  required ChargerFinder findChargers,
  double reserveFraction = 0.1,
  double searchStepKm = 5,
}) async {
  final stops = <ChargingStation>[];
  final used = <String>{};
  var usableKm = initialRangeKm * (1 - reserveFraction);
  var travelledKm = 0.0;
  var lastStopIndex = 0;

  for (var i = 1; i < route.length; i++) {
    travelledKm += distanceKm(route[i - 1], route[i]);
    if (travelledKm <= usableKm) continue;

    // route[i] is out of range, so search from the last reachable point back
    // towards the previous stop (or the origin, if we must charge first).
    ChargingStation? stop;
    var stopIndex = i - 1;
    var sinceLastSearch = double.infinity;
    final floor = stops.isEmpty ? 0 : lastStopIndex + 1;
    for (var j = i - 1; j >= floor; j--) {
      if (j < i - 1) sinceLastSearch += distanceKm(route[j + 1], route[j]);
      if (sinceLastSearch + 1e-6 < searchStepKm) continue;
      sinceLastSearch = 0;
      final found = await findChargers(route[j]);
      final fresh = found.where((s) => !used.contains(s.id));
      if (fresh.isNotEmpty) {
        stop = fresh.first;
        stopIndex = j;
        break;
      }
    }
    if (stop == null) throw NoChargerInRangeException(stops.length);

    stops.add(stop);
    used.add(stop.id);
    lastStopIndex = stopIndex;
    usableKm = rangeAfterChargeKm * (1 - reserveFraction);
    travelledKm = 0;
    for (var k = stopIndex + 1; k <= i; k++) {
      travelledKm += distanceKm(route[k - 1], route[k]);
    }
  }
  return stops;
}
