# Charger

Plan electric-vehicle road trips: pick where you're going, tell Charger your range and
battery level, and it finds charging stops along the route using Google Maps Platform.

- **Smart stops** – drives the route until your battery would hit a 10 % reserve, then
  picks the nearest charger, searching back along the route if none is close. After each
  stop it assumes you charge to 80 %.
- **Your location as the default start**, place autocomplete for both ends.
- **Open-now filter** for stations, trip summary (distance, drive time, stops) and
  tap-to-zoom on each stop.

## Setup

1. In Google Cloud, enable **Maps SDK for Android/iOS**, **Places API (New)** and
   **Routes API**, then create an API key. Restrict it to those APIs and to this app's
   package name / bundle ID — the key ships inside the app, so restrictions are what
   protect it.
2. Provide the key locally (all of these files are gitignored — never commit the key):
   - **Dart** (Places/Routes calls): `flutter run --dart-define=MAPS_API_KEY=your_key`
   - **Android** map tiles: add `MAPS_API_KEY=your_key` on its own line in
     `android/local.properties`
   - **iOS** map tiles: copy `ios/Flutter/Secrets.xcconfig.example` to
     `ios/Flutter/Secrets.xcconfig` and fill it in
3. `flutter pub get && flutter run --dart-define=MAPS_API_KEY=your_key`

## Development

```sh
flutter analyze
flutter test        # planner + polyline unit tests
flutter build apk --debug --dart-define=MAPS_API_KEY=your_key
```

Toolchain: Flutter 3.47, Gradle 9.3.1, AGP 9.1.0, Kotlin 2.4.0 (Kotlin DSL build files).
