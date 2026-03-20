# `flutter_app/lib/features/media`

Media-library feature code lives here.

This feature owns listing, detail view, browser uploads, worker-progress reconciliation, download, trash, favorites, and inline comment actions on the client.

Current slice on March 20, 2026:
- web uploads still use the browser-specific chunk reader so multipart PUTs can stream from `dart:html`
- Android and iOS now use native gallery picking via `image_picker`, with Android lost-data recovery and deterministic picker injection hooks for integration coverage
- signed thumbnail URLs are now cached with expiry-aware invalidation instead of being treated as permanent
