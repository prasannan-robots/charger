import 'package:charger/planner.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_places_flutter/google_places_flutter.dart';
import 'package:google_places_flutter/model/place_type.dart';
import 'package:google_places_flutter/model/prediction.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  _MapScreenState createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final TextEditingController _sourceController = TextEditingController();
  final TextEditingController _destinationController = TextEditingController();
  final TextEditingController _rangeController = TextEditingController();
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};
  bool _isLoading = false;
  final GroundData _map = GroundData();
  bool _searchByOpeningHours = false;
  LatLng _currentPosition = const LatLng(
      13.085758559399656, 80.1754404576725); // Example start location
// 11.387819148378416, 79.73058865396625
  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
  }

  Future<void> _getCurrentLocation() async {
    Position position = await _map.determinePosition();
    setState(() {
      _currentPosition = LatLng(position.latitude, position.longitude);
    });
  }

  void _showSearchOptionsDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Search Options'),
          content: const Text('Do you want to search by opening hours?'),
          actions: <Widget>[
            TextButton(
              child: const Text('No'),
              onPressed: () {
                setState(() {
                  _searchByOpeningHours = false;
                });
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text('Yes'),
              onPressed: () {
                setState(() {
                  _searchByOpeningHours = true;
                });
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Charger'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _showSearchOptionsDialog,
          ),
        ],
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: _currentPosition,
              zoom: 12,
            ),
            markers: _markers,
            polylines: _polylines,
            onMapCreated: (GoogleMapController controller) {},
          ),
          Positioned(
            left: 0,
            right: 0,
            child: Card(
                child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      children: [
                        GooglePlaceAutoCompleteTextField(
                          textEditingController: _sourceController,
                          googleAPIKey:
                              "AIzaSyD-tezFTBpKRVH1icGYGyJUP4SQPyUrPaE",
                          inputDecoration: const InputDecoration(
                              label: Text('Enter Source')),
                          debounceTime: 800, // default 600 ms,
                          countries: const [
                            "in",
                            "fr"
                          ], // optional by default null is set
                          isLatLngRequired:
                              true, // if you required coordinates from place detail
                          getPlaceDetailWithLatLng: (Prediction prediction) {
                            // this method will return latlng with place detail
                            print("placeDetails" + prediction.lng.toString());
                            _sourceController.text =
                                '${prediction.lat.toString()},${prediction.lng.toString()}';
                          }, // this callback is called when isLatLngRequired is true
                          itemClick: (Prediction prediction) {},
                          // if we want to make custom list item builder
                          itemBuilder: (context, index, Prediction prediction) {
                            return Container(
                              padding: const EdgeInsets.all(10),
                              child: Row(
                                children: [
                                  const Icon(Icons.location_on),
                                  const SizedBox(
                                    width: 7,
                                  ),
                                  Expanded(
                                      child: Text(
                                          "${prediction.description ?? ""}"))
                                ],
                              ),
                            );
                          },
                          // if you want to add seperator between list items
                          seperatedBuilder: const Divider(),
                          // want to show close icon
                          isCrossBtnShown: true,
                          // optional container padding
                          containerHorizontalPadding: 10,
                          // place type
                          placeType: PlaceType.geocode,
                        ),
                        const SizedBox(height: 10),
                        GooglePlaceAutoCompleteTextField(
                          textEditingController: _destinationController,
                          googleAPIKey:
                              "AIzaSyD-tezFTBpKRVH1icGYGyJUP4SQPyUrPaE",
                          inputDecoration: const InputDecoration(
                              label: Text('Enter Destination')),
                          debounceTime: 800, // default 600 ms,
                          countries: const [
                            "in",
                            "fr"
                          ], // optional by default null is set
                          isLatLngRequired:
                              true, // if you required coordinates from place detail
                          getPlaceDetailWithLatLng: (Prediction prediction) {
                            // this method will return latlng with place detail
                            print("placeDetails" + prediction.lng.toString());
                            _destinationController.text =
                                '${prediction.lat.toString()},${prediction.lng.toString()}';
                          }, // this callback is called when isLatLngRequired is true
                          itemClick: (Prediction prediction) {
                            // _destinationController.selection =
                            //     TextSelection.fromPosition(TextPosition(
                            //         offset:
                            //             prediction.description?.length ?? 0));
                          },
                          // if we want to make custom list item builder
                          itemBuilder: (context, index, Prediction prediction) {
                            return Container(
                              padding: const EdgeInsets.all(10),
                              child: Row(
                                children: [
                                  const Icon(Icons.location_on),
                                  const SizedBox(
                                    width: 7,
                                  ),
                                  Expanded(
                                      child: Text(
                                          "${prediction.description ?? ""}"))
                                ],
                              ),
                            );
                          },
                          // if you want to add seperator between list items
                          seperatedBuilder: const Divider(),
                          // want to show close icon
                          isCrossBtnShown: true,
                          // optional container padding
                          containerHorizontalPadding: 10,
                          // place type
                          placeType: PlaceType.geocode,
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _rangeController,
                          decoration: InputDecoration(
                            hintText: 'Enter vehicle range',
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8.0),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ],
                    ))),
          ),
          if (_isLoading)
            const Center(
              child: CircularProgressIndicator(),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          setState(() {
            _isLoading = true;
          });
          String source = _sourceController.text;
          String destination = _destinationController.text;
          double rangekm = double.tryParse(_rangeController.text) ?? 100.0;

          List<LatLng> routeData = await _map.calculateRoute(
              _parseLatLng(source), _parseLatLng(destination));
          double rangeKm = _map.estimateRange(40, rangekm);

          Set<Marker> chargingStations = await _map.selectChargingStations(
              routeData, rangeKm, _searchByOpeningHours);

          setState(() {
            _isLoading = false;
            _markers = chargingStations;
            _polylines = {
              Polyline(
                polylineId: const PolylineId("route"),
                points: routeData,
                color: Colors.blue,
                width: 5,
              ),
            };
          });
        },
        child: Icon(_isLoading ? Icons.rocket : Icons.directions),
      ),
    );
  }
}

LatLng _parseLatLng(String input) {
  final parts = input.split(',');
  if (parts.length == 2) {
    final lat = double.tryParse(parts[0].trim());
    final lng = double.tryParse(parts[1].trim());
    if (lat != null && lng != null) {
      return LatLng(lat, lng);
    }
  }
  return const LatLng(0.0, 0.0);
}
