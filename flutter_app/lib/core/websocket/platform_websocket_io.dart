import 'dart:io';

import 'platform_websocket_connection.dart';

Future<PlatformWebSocketConnection> connectPlatformWebSocket(
  Uri uri, {
  Map<String, String> headers = const <String, String>{},
}) async {
  final socket = await WebSocket.connect(
    uri.toString(),
    headers: headers.isEmpty ? null : headers,
  );
  return _IoPlatformWebSocketConnection(socket);
}

class _IoPlatformWebSocketConnection implements PlatformWebSocketConnection {
  _IoPlatformWebSocketConnection(this._socket);

  final WebSocket _socket;

  @override
  Stream<String> get messages =>
      _socket.where((message) => message is String).cast<String>();

  @override
  Future<void> close() async {
    await _socket.close(WebSocketStatus.normalClosure);
  }
}
