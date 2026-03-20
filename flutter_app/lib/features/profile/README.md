# `flutter_app/lib/features/profile`

Profile feature code lives here.

This feature now owns the current user's account summary, display-name editing, avatar upload flow, avatar-read status messaging, and storage-usage views.

Current slice on March 20, 2026:
- avatar picking now works on Android and iOS through native gallery UI instead of being web-only
- interrupted Android avatar selections can now be recovered and uploaded after relaunch
- profile avatar updates still refresh the shared signed-avatar cache through the auth + directory providers
