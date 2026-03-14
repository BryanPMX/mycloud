# `flutter_app/lib`

Primary Dart application code lives here.

The main areas are `core/`, `features/`, and `shared/`.

Current implemented slice:
- `main.dart` and `app.dart` bootstrap a real app shell
- `core/` holds environment config, endpoint helpers, routing, and theme setup
- `features/` now contains seeded auth, media, album, profile, admin, and comment surfaces that match the live backend contracts closely enough for the next integration pass
- `shared/` contains the adaptive scaffold plus small formatting utilities
