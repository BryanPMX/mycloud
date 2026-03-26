# `flutter_app/ios`

iOS-specific project files live here.

Only commit files that are part of the supported iOS build configuration. The native auth slice includes a Runner entitlements file so secure token storage can use the iOS keychain correctly, and the native media/avatar picker slice adds `NSPhotoLibraryUsageDescription` so iOS gallery access works through Apple photo-picking surfaces.

Release status on March 26, 2026:
- the Runner target now uses bundle id `live.mynube.app`
- the local Xcode team id discovered on this machine is `55BP75778A` (`BRYAN PEREZ`), and that team is now wired into the Runner project for automatic signing
- `flutter build ios --release --no-codesign` succeeds, so the remaining App Store blocker is certificate/provisioning setup rather than code compilation
- `security find-identity -v -p codesigning` currently reports `0 valid identities found`, so Xcode still needs an Apple Development or Apple Distribution certificate before signed archives can be exported
