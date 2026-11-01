import 'dart:convert';
import 'dart:math';

import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

import 'config.dart';

/// Thrown when a Google Maps Platform request fails. [message] is safe to show
/// to the user.
class ApiException implements Exception {
  ApiException(this.message);
  final String message;

  @override
  String toString() => message;
}

class PlaceSuggestion {
  const PlaceSuggestion({
    required this.placeId,
    required this.primaryText,
    required this.secondaryText,
  });

  final String placeId;
  final String primaryText;
  final String secondaryText;

  String get fullText =>
      secondaryText.isEmpty ? primaryText : '$primaryText, $secondaryText';
}

class ChargingStation {
  const ChargingStation({
    required this.id,
    required this.name,
    required this.position,
    this.address,
    this.openNow,
  });

  factory ChargingStation.fromPlace(Map<String, dynamic> place) {
    final location = place['location'] as Map<String, dynamic>;
    bool? openNow;
    for (final key in ['currentOpeningHours', 'regularOpeningHours']) {
      final hours = place[key];
      if (hours is Map && hours['openNow'] is bool) {
        openNow = hours['openNow'] as bool;
        break;
      }
    }
    return ChargingStation(
      id: place['id'] as String,
      name: (place['displayName']?['text'] as String?) ?? 'Charging station',
      address: place['formattedAddress'] as String?,
      position: LatLng(
        (location['latitude'] as num).toDouble(),
        (location['longitude'] as num).toDouble(),
      ),
      openNow: openNow,
    );
  }

  final String id;
  final String name;
  final LatLng position;
  final String? address;
  final bool? openNow;
}

class RouteResult {
  const RouteResult({
    required this.points,
    required this.distanceKm,
    required this.duration,
  });

  final List<LatLng> points;
  final double distanceKm;
  final Duration duration;
}

/// Thin client for the Google Maps Platform web services used by the app.
///
/// Every request sends an explicit field mask: Google bills Places and Routes
/// by the fields you ask for, and a `*` mask is charged at the most expensive
/// tier.
class GoogleMapsApi {
  GoogleMapsApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static const _placesBase = 'https://places.googleapis.com/v1';

  /// A new token per search session lets Google bill the autocomplete
  /// keystrokes and the final place lookup as a single session.
  static String newSessionToken() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  Map<String, String> _headers(String? fieldMask) => {
        'Content-Type': 'application/json',
        'X-Goog-Api-Key': mapsApiKey,
        if (fieldMask != null) 'X-Goog-FieldMask': fieldMask,
      };

  Future<List<PlaceSuggestion>> autocomplete(
    String input, {
    required String sessionToken,
    LatLng? near,
  }) async {
    final body = <String, dynamic>{
      'input': input,
      'sessionToken': sessionToken,
      if (near != null)
        'locationBias': {
          'circle': {
            'center': {'latitude': near.latitude, 'longitude': near.longitude},
            'radius': 50000.0,
          },
        },
    };
    // Autocomplete is billed per request, not per field, so no mask needed.
    final data = await _post('$_placesBase/places:autocomplete', body, null);
    final suggestions = (data['suggestions'] as List?) ?? const [];
    return [
      for (final s in suggestions)
        if (s['placePrediction'] case final Map<String, dynamic> p)
          PlaceSuggestion(
            placeId: p['placeId'] as String,
            primaryText:
                (p['structuredFormat']?['mainText']?['text'] as String?) ?? '',
            secondaryText:
                (p['structuredFormat']?['secondaryText']?['text'] as String?) ??
                    '',
          ),
    ];
  }

  Future<LatLng> placeLocation(String placeId, {String? sessionToken}) async {
    final uri = Uri.parse('$_placesBase/places/${Uri.encodeComponent(placeId)}')
        .replace(
      queryParameters: sessionToken == null ? null : {'sessionToken': sessionToken},
    );
    final response = await _client.get(uri, headers: _headers('location'));
    final data = _decode(response);
    final location = data['location'] as Map<String, dynamic>?;
    if (location == null) throw ApiException('That place has no location.');
    return LatLng(
      (location['latitude'] as num).toDouble(),
      (location['longitude'] as num).toDouble(),
    );
  }

  Future<RouteResult> computeRoute(LatLng origin, LatLng destination) async {
    Map<String, dynamic> waypoint(LatLng p) => {
          'location': {
            'latLng': {'latitude': p.latitude, 'longitude': p.longitude},
          },
        };
    final data = await _post(
      'https://routes.googleapis.com/directions/v2:computeRoutes',
      {
        'origin': waypoint(origin),
        'destination': waypoint(destination),
        'travelMode': 'DRIVE',
        'routingPreference': 'TRAFFIC_AWARE',
        'computeAlternativeRoutes': false,
        'languageCode': 'en-US',
        'units': 'METRIC',
      },
      'routes.duration,routes.distanceMeters,routes.polyline.encodedPolyline',
    );
    final routes = (data['routes'] as List?) ?? const [];
    if (routes.isEmpty) {
      throw ApiException('No driving route found between those places.');
    }
    final route = routes.first as Map<String, dynamic>;
    final seconds = int.tryParse(
          (route['duration'] as String? ?? '0s').replaceAll('s', ''),
        ) ??
        0;
    return RouteResult(
      points: decodePolyline(route['polyline']['encodedPolyline'] as String),
      distanceKm: ((route['distanceMeters'] as num?) ?? 0) / 1000.0,
      duration: Duration(seconds: seconds),
    );
  }

  /// EV charging stations near [at], nearest first.
  Future<List<ChargingStation>> nearbyChargers(
    LatLng at, {
    double radiusMeters = 5000,
    bool onlyOpenNow = false,
  }) async {
    final data = await _post(
      '$_placesBase/places:searchNearby',
      {
        'includedTypes': ['electric_vehicle_charging_station'],
        'maxResultCount': 10,
        'rankPreference': 'DISTANCE',
        'locationRestriction': {
          'circle': {
            'center': {'latitude': at.latitude, 'longitude': at.longitude},
            'radius': radiusMeters,
          },
        },
      },
      [
        'places.id',
        'places.displayName',
        'places.formattedAddress',
        'places.location',
        // Opening hours are a pricier field, so only ask when we filter on it.
        if (onlyOpenNow) ...[
          'places.currentOpeningHours',
          'places.regularOpeningHours',
        ],
      ].join(','),
    );
    final places = (data['places'] as List?) ?? const [];
    return places
        .cast<Map<String, dynamic>>()
        .map(ChargingStation.fromPlace)
        .where((s) => !onlyOpenNow || s.openNow == true)
        .toList();
  }

  Future<Map<String, dynamic>> _post(
    String url,
    Map<String, dynamic> body,
    String? fieldMask,
  ) async {
    final response = await _client.post(
      Uri.parse(url),
      headers: _headers(fieldMask),
      body: jsonEncode(body),
    );
    return _decode(response);
  }

  Map<String, dynamic> _decode(http.Response response) {
    Map<String, dynamic> data;
    try {
      data = response.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(response.body) as Map<String, dynamic>;
    } on FormatException {
      throw ApiException('Unexpected response (HTTP ${response.statusCode}).');
    }
    if (response.statusCode >= 400) {
      final message = data['error']?['message'] as String?;
      throw ApiException(message ?? 'Request failed (HTTP ${response.statusCode}).');
    }
    return data;
  }
}

/// Decodes a Google encoded polyline into coordinates.
List<LatLng> decodePolyline(String encoded) {
  final points = <LatLng>[];
  var index = 0, lat = 0, lng = 0;

  int nextValue() {
    var result = 0, shift = 0, b = 0;
    do {
      b = encoded.codeUnitAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    return (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
  }

  while (index < encoded.length) {
    lat += nextValue();
    lng += nextValue();
    points.add(LatLng(lat / 1e5, lng / 1e5));
  }
  return points;
}
