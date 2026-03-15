# `flutter_app/lib`

Primary Dart application code lives here.

The main areas are `core/`, `features/`, and `shared/`.

Current implemented slice:
- `main.dart` and `app.dart` bootstrap a real app shell
- `core/` holds environment config, endpoint helpers, a shared HTTP transport, connectivity status tracking, routing, and theme setup
- `features/` now contains live auth, media, album, profile, admin, comment, and family-directory/avatar-cache slices with demo-mode fallback for tests/offline walkthroughs
- `shared/` contains the adaptive scaffold, the shared avatar widget, and small formatting utilities
