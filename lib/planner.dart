import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'dart:convert';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class GroundData {
  Future<Position> determinePosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    // Test if location services are enabled.
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      // Location services are not enabled don't continue
      // accessing the position and request users of the
      // App to enable the location services.
      return Future.error('Location services are disabled.');
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        // Permissions are denied, next time you could try
        // requesting permissions again (this is also where
        // Android's shouldShowRequestPermissionRationale
        // returned true. According to Android guidelines
        // your App should show an explanatory UI now.
        return Future.error('Location permissions are denied');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      // Permissions are denied forever, handle appropriately.
      return Future.error(
          'Location permissions are permanently denied, we cannot request permissions.');
    }

    // When we reach here, permissions are granted and we can
    // continue accessing the position of the device.
    return await Geolocator.getCurrentPosition();
  }

  Future<Set<Marker>> fetchChargingStations(
      double latitude, double longitude, bool selectchargingopen) async {
    const url = 'https://places.googleapis.com/v1/places:searchNearby';
    final headers = {
      'Content-Type': 'application/json',
      'X-Goog-Api-Key': 'AIzaSyD-tezFTBpKRVH1icGYGyJUP4SQPyUrPaE',
      'X-Goog-FieldMask': '*',
    };
    String body = jsonEncode({
      'includedTypes': ['electric_vehicle_charging_station'],
      'maxResultCount': 10,
      'locationRestriction': {
        'circle': {
          'center': {
            'latitude': latitude,
            'longitude': longitude,
          },
          'radius': 500.0,
        },
      },
    });
    final response = await http.post(
      Uri.parse(url),
      headers: headers,
      body: body,
    );
    final Map<String, dynamic> jsonResponse = json.decode(response.body);
    final List<dynamic>? places =
        jsonResponse.containsKey('places') ? jsonResponse['places'] : null;

    if (places != null) {
      Set<Marker> markers = places
          .where((place) =>
              !selectchargingopen ||
              (place['currentOpeningHours'] != null &&
                  place['currentOpeningHours']['openNow'] == true) ||
              (place['regularOpeningHours'] != null &&
                  place['regularOpeningHours']['openNow'] == true))
          .map((place) {
        return Marker(
          markerId: MarkerId(place['displayName']['text']),
          position: LatLng(
              place['location']['latitude'], place['location']['longitude']),
          infoWindow: InfoWindow(title: place['displayName']['text']),
        );
      }).toSet();
      return markers;
    }
    return {};
  }

  Future<Set<Marker>> selectChargingStations(
      List<LatLng> routePoints, double rangeKm, bool selectchargingopen) async {
    Set<Marker> chargingStations = {};
    double traveledDistance = 0.0;

    for (int i = 1; i < routePoints.length; i++) {
      double stepDistance = Geolocator.distanceBetween(
            routePoints[i - 1].latitude,
            routePoints[i - 1].longitude,
            routePoints[i].latitude,
            routePoints[i].longitude,
          ) /
          1000.0; // Convert to km
      traveledDistance += stepDistance;

      if (traveledDistance >= rangeKm) {
        LatLng stepLocation = routePoints[i];
        // Fetch nearby charging stations using the Google Places API
        print('Checking for charging stations at $stepLocation');
        Set<Marker> nearbyStations = await fetchChargingStations(
            stepLocation.latitude, stepLocation.longitude, selectchargingopen);

        if (nearbyStations.isNotEmpty) {
          chargingStations
              .add(nearbyStations.first); // Select the nearest station
          traveledDistance = 0.0; // Reset distance after a charging stop
        } else {
          // Backtrack along the route points to check for chargers
          LatLng? lastCheckedLocation;
          print('Backtracking to check for charging stations');
          for (int j = i - 1; j >= 0; j--) {
            LatLng backtrackLocation = routePoints[j];
            if (lastCheckedLocation != null) {
              double backtrackDistance = Geolocator.distanceBetween(
                    lastCheckedLocation.latitude,
                    lastCheckedLocation.longitude,
                    backtrackLocation.latitude,
                    backtrackLocation.longitude,
                  ) /
                  1000.0; // Convert to km
              if (backtrackDistance < 1.0) {
                continue; // Skip points within 500 meters
              }
            }
            lastCheckedLocation = backtrackLocation;
            print(
                'BackTrack: Checking for charging stations at ${backtrackLocation.latitude} ${backtrackLocation.longitude} $j');

            Set<Marker> backtrackStations = await fetchChargingStations(
                backtrackLocation.latitude,
                backtrackLocation.longitude,
                selectchargingopen);

            if (backtrackStations.isNotEmpty) {
              chargingStations
                  .add(backtrackStations.first); // Select the nearest station
              traveledDistance = 0.0; // Reset distance after a charging stop
              break;
            }
          }
        }
      }
    }

    return chargingStations;
  }

  Future<List<LatLng>> calculateRoute(LatLng source, LatLng destination) async {
    final url = 'https://routes.googleapis.com/directions/v2:computeRoutes';
    final headers = {
      'Content-Type': 'application/json',
      'X-Goog-Api-Key': 'AIzaSyD-tezFTBpKRVH1icGYGyJUP4SQPyUrPaE',
      'X-Goog-FieldMask':
          'routes.duration,routes.distanceMeters,routes.polyline.encodedPolyline',
    };
    final body = jsonEncode({
      'origin': {
        'location': {
          'latLng': {
            'latitude': source.latitude,
            'longitude': source.longitude,
          },
        },
      },
      'destination': {
        'location': {
          'latLng': {
            'latitude': destination.latitude,
            'longitude': destination.longitude,
          },
        },
      },
      "travelMode": "DRIVE",
      "routingPreference": "TRAFFIC_AWARE_OPTIMAL",
      'computeAlternativeRoutes': false,
      'routeModifiers': {
        "vehicleInfo": {"emissionType": "ELECTRIC"},
        'avoidTolls': false,
        'avoidHighways': false,
        'avoidFerries': false,
      },
      "requestedReferenceRoutes": ["FUEL_EFFICIENT"],
      'languageCode': 'en-US',
      'units': 'IMPERIAL',
    });

    final response = await http.post(
      Uri.parse(url),
      headers: headers,
      body: body,
    );

    final data = json.decode(response.body);
    final encodedPolyline = data['routes'][0]['polyline']['encodedPolyline'];
    final List<LatLng> routePoints = decodePolyline(encodedPolyline);

    return routePoints;
  }

  List<LatLng> decodePolyline(String encoded) {
    List<LatLng> poly = [];
    int index = 0, len = encoded.length;
    int lat = 0, lng = 0;

    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += dlng;

      poly.add(LatLng(lat / 1E5, lng / 1E5));
    }

    return poly;
  }

  double estimateRange(double batteryPercentage, double fullRangeKm) {
    return (batteryPercentage / 100) * fullRangeKm;
  }
}
