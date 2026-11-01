import 'dart:math';

import 'package:charger/google_api.dart';
import 'package:charger/planner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// A straight route along the equator with a point every [stepKm].
List<LatLng> straightRoute(double lengthKm, {double stepKm = 1}) {
  const degPerKm = 360 / (2 * pi * 6371); // same Earth radius as the planner
  return [
    for (var km = 0.0; km <= lengthKm + 1e-9; km += stepKm)
      LatLng(0, km * degPerKm),
  ];
}

double kmAlong(LatLng p) => p.longitude * (2 * pi * 6371) / 360;

ChargingStation stationAt(LatLng p) => ChargingStation(
      id: 'st-${kmAlong(p).round()}',
      name: 'Station ${kmAlong(p).round()}',
      position: p,
    );

void main() {
  test('decodes Google sample polyline', () {
    final points = decodePolyline('_p~iF~ps|U_ulLnnqC_mqNvxq`@');
    expect(points.map((p) => [p.latitude, p.longitude]).toList(), [
      [38.5, -120.2],
      [40.7, -120.95],
      [43.252, -126.453],
    ]);
  });

  test('estimateRange scales and clamps the battery percentage', () {
    expect(estimateRange(50, 300), 150);
    expect(estimateRange(150, 300), 300);
    expect(estimateRange(-5, 300), 0);
  });

  test('short trip needs no charging and makes no API calls', () async {
    var calls = 0;
    final stops = await planChargingStops(
      route: straightRoute(50),
      initialRangeKm: 100,
      rangeAfterChargeKm: 100,
      findChargers: (at) async {
        calls++;
        return [stationAt(at)];
      },
    );
    expect(stops, isEmpty);
    expect(calls, 0);
  });

  test('stops before the battery reserve on a long trip', () async {
    final stops = await planChargingStops(
      route: straightRoute(250),
      initialRangeKm: 100, // 90 km usable with the 10% reserve
      rangeAfterChargeKm: 100,
      findChargers: (at) async => [stationAt(at)],
    );
    expect(stops.map((s) => kmAlong(s.position).round()), [90, 180]);
  });

  test('backtracks to an earlier charger but never past the last stop',
      () async {
    final searchedKm = <int>[];
    final stops = await planChargingStops(
      route: straightRoute(150),
      initialRangeKm: 100,
      rangeAfterChargeKm: 100,
      findChargers: (at) async {
        final km = kmAlong(at).round();
        searchedKm.add(km);
        // Only one charger exists, at km 60.
        return km == 60 ? [stationAt(at)] : const <ChargingStation>[];
      },
    );
    expect(stops.map((s) => kmAlong(s.position).round()), [60]);
    // Searched 90, 85, ..., 60 in 5 km steps, then nothing more was needed.
    expect(searchedKm.first, 90);
    expect(searchedKm.every((km) => km >= 60), isTrue);
  });

  test('throws when no charger is reachable', () async {
    expect(
      planChargingStops(
        route: straightRoute(200),
        initialRangeKm: 100,
        rangeAfterChargeKm: 100,
        findChargers: (_) async => const [],
      ),
      throwsA(isA<NoChargerInRangeException>()),
    );
  });
}
