# `flutter_app/lib/features/media/data`

Media data-source helpers live here.

Use this directory for browser/native file picking, upload-source adapters, and other feature-local integration helpers that should stay out of the UI layer.

Current implementation on March 20, 2026:
- `upload_picker_web.dart` keeps the browser-only multipart chunk reader
- `upload_picker_io.dart` now uses `image_picker` for Android/iOS gallery selection and recovers lost picker sessions on Android relaunch
- `xfile_selected_upload_file.dart` adapts native `XFile` handles into the chunked upload abstraction used by the multipart provider
