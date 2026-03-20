# `flutter_app/lib/core/connectivity`

Connectivity abstractions live here.

Use this directory to centralize network-state awareness and offline-related helpers.

Current implementation:
- `connectivity_service.dart` tracks `online`, `offline`, and `unknown` states for the app
- browser targets also listen to `window.onOnline`/`window.onOffline`
- shared HTTP transports now mark the app reachable on successful responses and unreachable on transport failures
- upload and avatar file-picking UX uses this state to avoid starting actions that cannot succeed while offline
- media favorites, comment mutations, album mutations, and album/share loads now also surface the same offline status instead of failing generically
