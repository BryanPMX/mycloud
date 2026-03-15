# `flutter_app`

This directory contains the Flutter client.

Current state on March 15, 2026:
- the app now boots a real `MaterialApp.router` shell
- the default path now uses the live backend for auth/session restore, media reads, albums, comments, and admin stats
- demo mode remains available through `--dart-define=USE_DEMO_DATA=true`
- `flutter analyze` and `flutter test` both pass

Keep cross-platform app code here, with platform-specific shells under `android/`, `ios/`, and `web/`. The next work is multipart uploads, `/ws/progress`, the remaining write flows, and secure native token persistence.
