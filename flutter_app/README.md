# `flutter_app`

This directory contains the Flutter client.

Current state on March 15, 2026:
- the app now boots a real `MaterialApp.router` shell
- the default path now uses the live backend for auth/session restore, media reads, albums, comments, and admin stats
- the browser path now supports multipart uploads plus `/ws/progress` processing updates
- demo mode remains available through `--dart-define=USE_DEMO_DATA=true`
- `flutter analyze` and `flutter test` both pass

Keep cross-platform app code here, with platform-specific shells under `android/`, `ios/`, and `web/`. The next work is the remaining write flows, secure native token persistence, richer admin tooling, and the broader mobile/offline polish.
