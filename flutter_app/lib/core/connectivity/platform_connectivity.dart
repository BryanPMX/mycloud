import 'platform_connectivity_io.dart'
    if (dart.library.html) 'platform_connectivity_web.dart' as platform;

bool? currentPlatformOnlineState() => platform.currentPlatformOnlineState();

void Function()? registerPlatformConnectivityListener(
  void Function(bool isOnline) onChanged,
) {
  return platform.registerPlatformConnectivityListener(onChanged);
}
