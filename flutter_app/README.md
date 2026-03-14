# `flutter_app`

This directory contains the Flutter client.

Current state on March 14, 2026:
- the app now boots a real `MaterialApp.router` shell
- the current implementation is SDK-only and uses seeded state to mirror the live backend contracts
- `flutter analyze` and `flutter test test/core/smoke_test.dart` both pass

Keep cross-platform app code here, with platform-specific shells under `android/`, `ios/`, and `web/`. The next work is wiring the current shell to `/auth`, `/users/me`, `/media`, `/albums`, and the upload/WebSocket endpoints.
