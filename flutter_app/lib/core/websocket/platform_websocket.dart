import 'platform_websocket_connection.dart';
import 'platform_websocket_io.dart'
    if (dart.library.html) 'platform_websocket_web.dart' as platform_websocket;

Future<PlatformWebSocketConnection> connectPlatformWebSocket(
  Uri uri, {
  Map<String, String> headers = const <String, String>{},
}) {
  return platform_websocket.connectPlatformWebSocket(uri, headers: headers);
}
