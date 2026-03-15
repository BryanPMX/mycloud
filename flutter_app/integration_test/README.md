# `flutter_app/integration_test`

End-to-end and high-level integration tests live here.

Current coverage:
- `app_happy_paths_test.dart` runs seeded demo admin and member happy paths with `IntegrationTestWidgetsFlutterBinding`, covering app boot, auth, library interactions, album sharing, profile edits, and admin invite flows

Run this suite with `flutter test integration_test` on a supported non-web device target.
