// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:html' as html;

import 'platform_websocket_connection.dart';

Future<PlatformWebSocketConnection> connectPlatformWebSocket(
  Uri uri, {
  Map<String, String> headers = const <String, String>{},
}) async {
  final socket = html.WebSocket(uri.toString());
  final controller = StreamController<String>();
  final openCompleter = Completer<void>();

  late final StreamSubscription<html.Event> openSubscription;
  late final StreamSubscription<html.Event> errorSubscription;
  late final StreamSubscription<html.CloseEvent> closeSubscription;
  late final StreamSubscription<html.MessageEvent> messageSubscription;

  Object connectionError([String? message]) {
    return StateError(
        message ?? 'Unable to connect to the progress websocket.');
  }

  void failOpen([String? message]) {
    if (!openCompleter.isCompleted) {
      openCompleter.completeError(connectionError(message));
    }
  }

  openSubscription = socket.onOpen.listen((_) {
    if (!openCompleter.isCompleted) {
      openCompleter.complete();
    }
  });

  errorSubscription = socket.onError.listen((_) {
    controller.addError(connectionError());
    failOpen();
  });

  closeSubscription = socket.onClose.listen((event) {
    final reason = event.reason?.trim();
    failOpen(reason == null || reason.isEmpty ? null : reason);
    if (!controller.isClosed) {
      unawaited(controller.close());
    }
  });

  messageSubscription = socket.onMessage.listen((event) {
    final data = event.data;
    if (data is String) {
      controller.add(data);
    }
  });

  await openCompleter.future;
  return _WebPlatformWebSocketConnection(
    socket: socket,
    stream: controller.stream,
    controller: controller,
    subscriptions: <StreamSubscription<dynamic>>[
      openSubscription,
      errorSubscription,
      closeSubscription,
      messageSubscription,
    ],
  );
}

class _WebPlatformWebSocketConnection implements PlatformWebSocketConnection {
  _WebPlatformWebSocketConnection({
    required html.WebSocket socket,
    required Stream<String> stream,
    required StreamController<String> controller,
    required List<StreamSubscription<dynamic>> subscriptions,
  })  : _socket = socket,
        _stream = stream,
        _controller = controller,
        _subscriptions = subscriptions;

  final html.WebSocket _socket;
  final Stream<String> _stream;
  final StreamController<String> _controller;
  final List<StreamSubscription<dynamic>> _subscriptions;

  @override
  Stream<String> get messages => _stream;

  @override
  Future<void> close() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }

    if (_socket.readyState == html.WebSocket.CONNECTING ||
        _socket.readyState == html.WebSocket.OPEN) {
      _socket.close(1000, 'client_closed');
    }

    if (!_controller.isClosed) {
      await _controller.close();
    }
  }
}
