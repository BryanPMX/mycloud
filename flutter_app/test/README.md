# `flutter_app/test`

Client unit and widget tests live here.

Group tests by core, features, and shared UI concerns for easy discovery.

Current coverage:
- `test/core/smoke_test.dart` boots the app and exercises the seeded demo member/admin happy paths through media, album, profile, and admin surfaces
- `test/core/connectivity_service_test.dart` verifies offline/online state transitions and browser-listener wiring for the shared connectivity service
- `test/shared/demo_app_harness.dart` keeps the widget and integration suites aligned on the same demo boot/sign-in helpers
