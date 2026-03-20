# `flutter_app/ios`

iOS-specific project files live here.

Only commit files that are part of the supported iOS build configuration. The native auth slice now includes a Runner entitlements file so secure token storage can use the iOS keychain correctly, and the native media/avatar picker slice now adds `NSPhotoLibraryUsageDescription` so iOS gallery access works through Apple photo-picking surfaces.
