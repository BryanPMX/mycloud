# `flutter_app`

This directory contains the Flutter client.

Current state on March 15, 2026:
- the app now boots a real `MaterialApp.router` shell
- the default path now uses the live backend for auth/session restore, media reads, comment threads, owned album CRUD, album sharing and membership writes, profile display-name/avatar edits, the non-admin family directory, and admin stats plus user management
- the browser path now supports multipart uploads plus `/ws/progress` processing updates
- the runtime now tracks browser and transport reachability through `core/connectivity/`, exposes that status in the shell, and disables upload/avatar picking while the app is offline
- native/mobile auth restore now persists tokens through secure storage instead of relying on browser cookies
- signed avatar URLs are now cached by `user_id` and refreshed through `GET /users/:id/avatar`, so profile, album sharing, comments, and the shell badge can reuse the same avatar-read flow
- demo mode remains available through `--dart-define=USE_DEMO_DATA=true`
- `flutter analyze` and `flutter test` both pass, and the new `integration_test/` suite is checked in for supported non-web devices

Keep cross-platform app code here, with platform-specific shells under `android/`, `ios/`, and `web/`. The next work is broader native media picking, offline/cache invalidation polish beyond upload/avatar actions, and live-backend end-to-end coverage around reconnect behavior.
