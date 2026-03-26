# `flutter_app/android`

Android-specific project files live here.

Only commit files that are part of the supported Android build configuration. The native auth slice keeps `minSdk` at 23 and disables app backup so secure token storage does not get restored onto a mismatched keystore. Native media/avatar picking runs through the Android system photo picker path exposed by `image_picker`, and the Flutter app recovers interrupted picker results on relaunch.

Release status on March 26, 2026:
- the Android app id and namespace now use `live.mynube.app`
- the launcher label now matches the production brand `Mynube`
- release signing now reads from `key.properties` when present, with a tracked `key.properties.example` template checked in for setup
- `flutter build appbundle --release` succeeds in this workspace; without `key.properties` it still falls back to the debug keystore, which is acceptable for local verification only and not for Play Store upload
