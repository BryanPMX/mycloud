# `flutter_app/integration_test`

End-to-end and high-level integration tests live here.

Current coverage:
- `app_happy_paths_test.dart` runs seeded demo admin and member happy paths with `IntegrationTestWidgetsFlutterBinding`, covering app boot, auth, library interactions, album sharing, profile edits, and admin invite flows
- `live_backend_upload_reconnect_test.dart` adds a live-backend variant for upload/reconnect wiring by injecting a deterministic test file, then forcing `/ws/progress` to reconnect; it skips unless `ITEST_LIVE_EMAIL` and `ITEST_LIVE_PASSWORD` are provided

Latest verification on March 20, 2026:
- `flutter test integration_test -d <ios-simulator>` passes on the local iOS simulator
- the live-backend case is compiled and part of the suite, but it remains skipped in this workspace until live credentials are supplied

Run this suite with `flutter test integration_test -d <device-id>` on a supported non-web device target.
