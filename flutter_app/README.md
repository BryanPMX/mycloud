# `flutter_app`

This directory contains the Flutter client.

Current state on March 20, 2026:
- the app now boots a real `MaterialApp.router` shell
- the default path now uses the live backend for auth/session restore, media reads, comment threads, owned album CRUD, album sharing and membership writes, profile display-name/avatar edits, the non-admin family directory, and admin stats plus user management
- browser uploads still use the custom HTML multipart picker, while Android and iOS now use native gallery pickers through `image_picker`, including Android lost-picker recovery on relaunch
- the runtime now tracks browser and transport reachability through `core/connectivity/`, exposes that status in the shell, and blocks upload, avatar, favorites, comments, and album mutations while the app is offline
- native/mobile auth restore now persists tokens through secure storage instead of relying on browser cookies
- signed avatar URLs are now cached by `user_id` and refreshed through `GET /users/:id/avatar`, and media thumbnails now use the same TTL-aware signed-URL cache pattern through `GET /media/:id/thumb`
- demo mode remains available through `--dart-define=USE_DEMO_DATA=true`
- `flutter analyze`, `flutter test`, and `flutter test integration_test -d <ios-simulator>` now pass; the new live-backend upload/reconnect integration test is checked in and skips unless `ITEST_LIVE_EMAIL` plus `ITEST_LIVE_PASSWORD` are provided

Keep cross-platform app code here, with platform-specific shells under `android/`, `ios/`, and `web/`. The main remaining follow-up is to run the live-backend upload/reconnect variant with real test credentials and to set a real `version:` field in `pubspec.yaml` so iOS builds stop warning about missing bundle metadata.
