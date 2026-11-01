import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'config.dart';
import 'google_api.dart';
import 'location.dart';
import 'planner.dart';
import 'widgets/place_field.dart';

/// Battery level the planner assumes you charge to at each stop (typical for
/// DC fast charging, which slows down sharply above ~80%).
const double chargeToPercent = 80;

class MapScreen extends StatefulWidget {
  const MapScreen({super.key, this.api});

  /// Injectable for tests; defaults to the real Google Maps Platform client.
  final GoogleMapsApi? api;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  static const _fallbackCenter = LatLng(13.0858, 80.1754); // Chennai

  late final GoogleMapsApi _api = widget.api ?? GoogleMapsApi();
  final _rangeController = TextEditingController(text: '300');
  GoogleMapController? _map;

  LatLng? _here;
  SelectedPlace? _origin;
  SelectedPlace? _destination;
  double _batteryPercent = 80;
  bool _onlyOpenNow = false;
  bool _panelExpanded = true;
  bool _planning = false;

  RouteResult? _route;
  List<ChargingStation> _stops = const [];

  @override
  void initState() {
    super.initState();
    _locate();
  }

  @override
  void dispose() {
    _rangeController.dispose();
    _map?.dispose();
    super.dispose();
  }

  Future<void> _locate({bool userAsked = false}) async {
    try {
      final position = await determinePosition();
      if (!mounted) return;
      final here = LatLng(position.latitude, position.longitude);
      setState(() => _here = here);
      if (userAsked || _route == null) {
        await _map?.animateCamera(CameraUpdate.newLatLngZoom(here, 13));
      }
    } on Exception catch (e) {
      if (userAsked && mounted) _showMessage(e.toString());
    }
  }

  Future<void> _plan() async {
    FocusScope.of(context).unfocus();
    final origin = _origin?.position ?? _here;
    final destination = _destination?.position;
    final fullRangeKm = double.tryParse(_rangeController.text.trim());

    final problem = !hasMapsApiKey
        ? 'No Maps API key. Run with --dart-define=MAPS_API_KEY=your_key.'
        : origin == null
            ? 'Pick a starting point (your location is unavailable).'
            : destination == null
                ? 'Pick a destination from the suggestions.'
                : fullRangeKm == null || fullRangeKm <= 0
                    ? "Enter your car's range on a full charge, in km."
                    : null;
    if (problem != null) {
      _showMessage(problem);
      return;
    }

    setState(() => _planning = true);
    try {
      final route = await _api.computeRoute(origin!, destination!);
      final stops = await planChargingStops(
        route: route.points,
        initialRangeKm: estimateRange(_batteryPercent, fullRangeKm!),
        rangeAfterChargeKm: estimateRange(chargeToPercent, fullRangeKm),
        findChargers: (at) => _api.nearbyChargers(at, onlyOpenNow: _onlyOpenNow),
      );
      if (!mounted) return;
      setState(() {
        _route = route;
        _stops = stops;
        _panelExpanded = false;
      });
      await _fitRoute(route.points);
    } on Exception catch (e) {
      if (mounted) _showMessage(e.toString());
    } finally {
      if (mounted) setState(() => _planning = false);
    }
  }

  Future<void> _fitRoute(List<LatLng> points) async {
    if (points.isEmpty || _map == null) return;
    var south = points.first.latitude, north = south;
    var west = points.first.longitude, east = west;
    for (final p in points) {
      if (p.latitude < south) south = p.latitude;
      if (p.latitude > north) north = p.latitude;
      if (p.longitude < west) west = p.longitude;
      if (p.longitude > east) east = p.longitude;
    }
    await _map!.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(south, west),
          northeast: LatLng(north, east),
        ),
        64,
      ),
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Set<Marker> get _markers {
    final route = _route;
    if (route == null || route.points.isEmpty) return const {};
    return {
      Marker(
        markerId: const MarkerId('origin'),
        position: route.points.first,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: InfoWindow(title: _origin?.label ?? 'Start'),
      ),
      Marker(
        markerId: const MarkerId('destination'),
        position: route.points.last,
        infoWindow: InfoWindow(title: _destination?.label ?? 'Destination'),
      ),
      for (final (i, stop) in _stops.indexed)
        Marker(
          markerId: MarkerId('stop-${stop.id}'),
          position: stop.position,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          infoWindow: InfoWindow(
            title: 'Stop ${i + 1}: ${stop.name}',
            snippet: stop.address,
          ),
        ),
    };
  }

  Set<Polyline> get _polylines {
    final route = _route;
    if (route == null) return const {};
    return {
      Polyline(
        polylineId: const PolylineId('route'),
        points: route.points,
        color: Theme.of(context).colorScheme.primary,
        width: 5,
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: _here ?? _fallbackCenter,
              zoom: 12,
            ),
            markers: _markers,
            polylines: _polylines,
            myLocationEnabled: _here != null,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            onMapCreated: (controller) => _map = controller,
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  _panelExpanded ? _buildPlannerCard() : _buildCollapsedBar(),
                  const Spacer(),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FloatingActionButton.small(
                      heroTag: 'locate',
                      tooltip: 'My location',
                      onPressed: () => _locate(userAsked: true),
                      child: const Icon(Icons.my_location),
                    ),
                  ),
                  if (_route != null && !_panelExpanded) ...[
                    const SizedBox(height: 12),
                    _buildSummaryCard(),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlannerCard() {
    final theme = Theme.of(context);
    return Card(
      elevation: 4,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.ev_station, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Text('Plan an EV trip', style: theme.textTheme.titleMedium),
                  const Spacer(),
                  if (_route != null)
                    IconButton(
                      tooltip: 'Hide planner',
                      icon: const Icon(Icons.expand_less),
                      onPressed: () => setState(() => _panelExpanded = false),
                    ),
                ],
              ),
              if (!hasMapsApiKey) ...[
                const SizedBox(height: 8),
                Material(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      'Maps API key missing. Build with '
                      '--dart-define=MAPS_API_KEY=your_key (see README).',
                      style: TextStyle(color: theme.colorScheme.onErrorContainer),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              PlaceField(
                api: _api,
                label: 'From',
                hint: 'Current location',
                icon: Icons.trip_origin,
                near: _here,
                onChanged: (place) => _origin = place,
              ),
              const SizedBox(height: 12),
              PlaceField(
                api: _api,
                label: 'To',
                icon: Icons.flag_outlined,
                near: _here,
                onChanged: (place) => _destination = place,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _rangeController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Range on a full charge',
                  suffixText: 'km',
                  prefixIcon: Icon(Icons.speed),
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.battery_charging_full, size: 20),
                  const SizedBox(width: 8),
                  Text('Battery now', style: theme.textTheme.bodyMedium),
                  Expanded(
                    child: Slider(
                      value: _batteryPercent,
                      min: 5,
                      max: 100,
                      divisions: 19,
                      label: '${_batteryPercent.round()}%',
                      onChanged: (v) => setState(() => _batteryPercent = v),
                    ),
                  ),
                  SizedBox(
                    width: 44,
                    child: Text(
                      '${_batteryPercent.round()}%',
                      textAlign: TextAlign.end,
                      style: theme.textTheme.labelLarge,
                    ),
                  ),
                ],
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('Only stations open now'),
                value: _onlyOpenNow,
                onChanged: (v) => setState(() => _onlyOpenNow = v),
              ),
              const SizedBox(height: 4),
              FilledButton.icon(
                onPressed: _planning ? null : _plan,
                icon: _planning
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.route),
                label: Text(_planning ? 'Finding chargers…' : 'Plan route'),
              ),
              const SizedBox(height: 6),
              Text(
                'Stops keep a 10% reserve and assume you charge to '
                '${chargeToPercent.round()}%.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCollapsedBar() {
    return Card(
      elevation: 4,
      child: ListTile(
        leading: const Icon(Icons.ev_station),
        title: Text(
          '${_origin?.label ?? 'Current location'} → '
          '${_destination?.label ?? 'Destination'}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.edit),
        onTap: () => setState(() => _panelExpanded = true),
      ),
    );
  }

  Widget _buildSummaryCard() {
    final theme = Theme.of(context);
    final route = _route!;
    final hours = route.duration.inHours;
    final minutes = route.duration.inMinutes.remainder(60);
    return Card(
      elevation: 4,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.35,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            ListTile(
              title: Text(
                '${route.distanceKm.toStringAsFixed(0)} km · '
                '${hours > 0 ? '${hours}h ' : ''}${minutes}min driving',
                style: theme.textTheme.titleMedium,
              ),
              subtitle: Text(
                _stops.isEmpty
                    ? 'No charging needed on this trip.'
                    : '${_stops.length} charging '
                        '${_stops.length == 1 ? 'stop' : 'stops'}',
              ),
            ),
            for (final (i, stop) in _stops.indexed)
              ListTile(
                dense: true,
                leading: CircleAvatar(
                  radius: 14,
                  child: Text('${i + 1}', style: theme.textTheme.labelMedium),
                ),
                title: Text(stop.name),
                subtitle: stop.address == null ? null : Text(stop.address!),
                trailing: stop.openNow == true
                    ? Text(
                        'Open',
                        style: TextStyle(color: theme.colorScheme.primary),
                      )
                    : null,
                onTap: () async {
                  await _map?.animateCamera(
                    CameraUpdate.newLatLngZoom(stop.position, 15),
                  );
                  await _map?.showMarkerInfoWindow(MarkerId('stop-${stop.id}'));
                },
              ),
          ],
        ),
      ),
    );
  }
}
