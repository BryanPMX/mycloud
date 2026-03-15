// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:html' as html;

bool? currentPlatformOnlineState() => html.window.navigator.onLine;

void Function()? registerPlatformConnectivityListener(
  void Function(bool isOnline) onChanged,
) {
  final onlineSubscription = html.window.onOnline.listen((_) {
    onChanged(true);
  });
  final offlineSubscription = html.window.onOffline.listen((_) {
    onChanged(false);
  });

  return () {
    unawaited(onlineSubscription.cancel());
    unawaited(offlineSubscription.cancel());
  };
}
