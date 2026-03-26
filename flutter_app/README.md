# `flutter_app`

This directory contains the Flutter client.

Current state on March 26, 2026:
- the app now boots a real `MaterialApp.router` shell
- the default path now uses the live backend for auth/session restore, media reads, comment threads, owned album CRUD, album sharing and membership writes, profile display-name/avatar edits, the non-admin family directory, and admin stats plus user management
- browser uploads still use the custom HTML multipart picker, while Android and iOS now use native gallery pickers through `image_picker`, including Android lost-picker recovery on relaunch
- the runtime now tracks browser and transport reachability through `core/connectivity/`, exposes that status in the shell, and blocks upload, avatar, favorites, comments, and album mutations while the app is offline
- native/mobile auth restore now persists tokens through secure storage instead of relying on browser cookies
- signed avatar URLs are now cached by `user_id` and refreshed through `GET /users/:id/avatar`, and media thumbnails now use the same TTL-aware signed-URL cache pattern through `GET /media/:id/thumb`
- release metadata is now set to `version: 1.0.0+1`
- Android release builds now use the production app id `live.mynube.app`, keep `minSdk` at 23, and read release signing data from `android/key.properties` when present
- iOS now uses the same `live.mynube.app` bundle identifier and has the local Xcode team id `55BP75778A` wired into the Runner target for automatic signing
- device-visible app branding is now aligned on `Mynube` instead of the old `familycloud` placeholder
- demo mode remains available through `--dart-define=USE_DEMO_DATA=true`
- `flutter analyze`, `flutter test`, `scripts/deploy-web.sh`, `flutter build ios --release --no-codesign`, and `flutter build appbundle --release` all pass in this workspace; the live-backend upload/reconnect integration test is still checked in and skips unless `ITEST_LIVE_EMAIL` plus `ITEST_LIVE_PASSWORD` are provided

Keep cross-platform app code here, with platform-specific shells under `android/`, `ios/`, and `web/`. The main remaining release follow-up is to install real Apple Distribution credentials in Xcode, create the Android upload keystore from `android/key.properties.example`, run the live-backend upload/reconnect variant with real credentials, and then produce a signed iOS archive plus Play Store `.aab`.
