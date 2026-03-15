# `flutter_app/android`

Android-specific project files live here.

Only commit files that are part of the supported Android build configuration. The native auth slice now keeps `minSdk` at 23 and disables app backup so secure token storage does not get restored onto a mismatched keystore.
