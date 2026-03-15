# `flutter_app`

This directory contains the Flutter client.

Current state on March 15, 2026:
- the app now boots a real `MaterialApp.router` shell
- the default path now uses the live backend for auth/session restore, media reads, comment threads, owned album CRUD, album sharing and membership writes, profile display-name/avatar edits, and admin stats plus user management
- the browser path now supports multipart uploads plus `/ws/progress` processing updates
- native/mobile auth restore now persists tokens through secure storage instead of relying on browser cookies
- demo mode remains available through `--dart-define=USE_DEMO_DATA=true`
- `flutter analyze` and `flutter test` both pass

Keep cross-platform app code here, with platform-specific shells under `android/`, `ios/`, and `web/`. The next work is consuming the new signed-avatar and `/users/directory` backend surfaces in Flutter, plus the broader mobile/offline polish beyond the current browser-first upload path.
