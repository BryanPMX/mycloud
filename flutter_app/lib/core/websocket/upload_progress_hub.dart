import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../features/auth/providers/auth_provider.dart';
import '../../features/media/domain/media.dart';
import '../../features/media/providers/media_list_provider.dart';
import '../../features/media/providers/media_upload_provider.dart';
import '../config/app_config.dart';
import 'platform_websocket.dart';
import 'platform_websocket_connection.dart';
import 'upload_progress_event.dart';

enum UploadProgressConnectionStatus {
  disconnected,
  connecting,
  connected,
  reconnecting,
}

class UploadProgressHub extends ChangeNotifier {
  UploadProgressHub({
    required AppConfig config,
    required AuthProvider authProvider,
    required MediaListProvider mediaProvider,
    required MediaUploadProvider uploadProvider,
  })  : _config = config,
        _authProvider = authProvider,
        _mediaProvider = mediaProvider,
        _uploadProvider = uploadProvider {
    _authProvider.addListener(_handleAuthChanged);
    if (_authProvider.isAuthenticated && !_config.useDemoData) {
      unawaited(ensureConnected());
    }
  }

  final AppConfig _config;
  final AuthProvider _authProvider;
  final MediaListProvider _mediaProvider;
  final MediaUploadProvider _uploadProvider;

  UploadProgressConnectionStatus _status =
      UploadProgressConnectionStatus.disconnected;
  String? _errorMessage;
  PlatformWebSocketConnection? _connection;
  StreamSubscription<String>? _messageSubscription;
  Timer? _reconnectTimer;
  bool _isConnecting = false;
  bool _isDisposed = false;

  UploadProgressConnectionStatus get status => _status;

  String? get errorMessage => _errorMessage;

  bool get isConnected => _status == UploadProgressConnectionStatus.connected;

  String get statusLabel {
    switch (_status) {
      case UploadProgressConnectionStatus.disconnected:
        return 'Offline';
      case UploadProgressConnectionStatus.connecting:
        return 'Connecting';
      case UploadProgressConnectionStatus.connected:
        return 'Live';
      case UploadProgressConnectionStatus.reconnecting:
        return 'Reconnecting';
    }
  }

  Future<void> ensureConnected() async {
    if (_config.useDemoData ||
        !_authProvider.isAuthenticated ||
        _isConnecting ||
        _isDisposed ||
        _connection != null) {
      return;
    }

    _setStatus(
      _status == UploadProgressConnectionStatus.disconnected
          ? UploadProgressConnectionStatus.connecting
          : UploadProgressConnectionStatus.reconnecting,
    );
    _isConnecting = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final headers = await _authProvider.websocketHeaders();
      if (!_authProvider.isAuthenticated || _isDisposed) {
        return;
      }

      final connection = await connectPlatformWebSocket(
        _config.websocketUri,
        headers: headers,
      );
      if (_isDisposed || !_authProvider.isAuthenticated) {
        await connection.close();
        return;
      }

      _connection = connection;
      _messageSubscription = connection.messages.listen(
        _handleMessage,
        onError: (_) => _handleConnectionDrop(),
        onDone: _handleConnectionDrop,
      );
      _reconnectTimer?.cancel();
      _errorMessage = null;
      _setStatus(UploadProgressConnectionStatus.connected);
    } catch (_) {
      _errorMessage = 'Unable to connect to upload progress updates.';
      _setStatus(UploadProgressConnectionStatus.reconnecting);
      _scheduleReconnect();
    } finally {
      _isConnecting = false;
    }
  }

  Future<void> retryNow() async {
    _reconnectTimer?.cancel();
    await _closeConnection();
    await ensureConnected();
  }

  @visibleForTesting
  Future<void> simulateConnectionDrop() async {
    if (_isDisposed) {
      return;
    }

    await _closeConnection();
    _handleConnectionDrop();
  }

  void _handleAuthChanged() {
    if (_config.useDemoData) {
      _errorMessage = null;
      _setStatus(UploadProgressConnectionStatus.disconnected);
      unawaited(_closeConnection());
      return;
    }

    if (_authProvider.isAuthenticated) {
      unawaited(ensureConnected());
      return;
    }

    _errorMessage = null;
    _reconnectTimer?.cancel();
    _setStatus(UploadProgressConnectionStatus.disconnected);
    unawaited(_closeConnection());
  }

  void _handleMessage(String rawMessage) {
    try {
      final decoded = jsonDecode(rawMessage);
      final payload = decoded is Map<String, dynamic>
          ? decoded
          : decoded is Map
              ? Map<String, dynamic>.from(decoded)
              : throw const FormatException('Invalid upload progress payload.');
      final event = UploadProgressEvent.fromJson(payload);
      _uploadProvider.applyProgressEvent(event);

      switch (event.type) {
        case UploadProgressEventType.processingStarted:
          _mediaProvider.updateProcessingStatus(
            event.mediaId,
            status: MediaStatus.pending,
          );
        case UploadProgressEventType.processingComplete:
          _mediaProvider.updateProcessingStatus(
            event.mediaId,
            status: MediaStatus.fromApi(event.status ?? 'ready'),
            smallThumbKey: event.thumbKeys?.small,
            mediumThumbKey: event.thumbKeys?.medium,
            largeThumbKey: event.thumbKeys?.large,
            posterThumbKey: event.thumbKeys?.poster,
          );
          unawaited(_mediaProvider.refreshMediaItem(event.mediaId));
        case UploadProgressEventType.processingFailed:
          _mediaProvider.updateProcessingStatus(
            event.mediaId,
            status: MediaStatus.failed,
          );
          unawaited(_mediaProvider.refreshMediaItem(event.mediaId));
      }
    } catch (_) {
      // Ignore malformed messages so the socket stays alive for valid events.
    }
  }

  void _handleConnectionDrop() {
    if (_isDisposed) {
      return;
    }

    unawaited(_closeConnection());
    if (!_authProvider.isAuthenticated || _config.useDemoData) {
      _errorMessage = null;
      _setStatus(UploadProgressConnectionStatus.disconnected);
      return;
    }

    _errorMessage = 'Upload progress updates disconnected. Retrying...';
    _setStatus(UploadProgressConnectionStatus.reconnecting);
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 2), () {
      unawaited(ensureConnected());
    });
  }

  Future<void> _closeConnection() async {
    final subscription = _messageSubscription;
    _messageSubscription = null;
    await subscription?.cancel();

    final connection = _connection;
    _connection = null;
    await connection?.close();
  }

  void _setStatus(UploadProgressConnectionStatus nextStatus) {
    if (_status == nextStatus) {
      notifyListeners();
      return;
    }

    _status = nextStatus;
    notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _reconnectTimer?.cancel();
    _authProvider.removeListener(_handleAuthChanged);
    unawaited(_closeConnection());
    super.dispose();
  }
}
