/// Google Maps Platform API key used for the Places and Routes web services.
///
/// It is injected at build time so it never lives in source control:
///
/// ```sh
/// flutter run --dart-define=MAPS_API_KEY=your_key
/// ```
///
/// The Android Maps SDK reads the same key from `android/local.properties`
/// (`MAPS_API_KEY=...`); see the README.
const String mapsApiKey = String.fromEnvironment('MAPS_API_KEY');

bool get hasMapsApiKey => mapsApiKey.isNotEmpty;
