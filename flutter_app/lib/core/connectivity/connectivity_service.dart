import 'package:flutter/foundation.dart';

import 'platform_connectivity.dart';

typedef ConnectivityListenerRegistrar = void Function()? Function(
    void Function(bool isOnline) onChanged);

enum ConnectivityStatus { unknown, online, offline }

class ConnectivityService extends ChangeNotifier {
  ConnectivityService({
    DateTime Function()? clock,
    bool? initialPlatformOnline,
    ConnectivityListenerRegistrar? registerPlatformListener,
  }) : _clock = clock ?? DateTime.now {
    final initialStatus = initialPlatformOnline ?? currentPlatformOnlineState();
    if (initialStatus != null) {
      _status = initialStatus
          ? ConnectivityStatus.online
          : ConnectivityStatus.offline;
    }

    final registrar =
        registerPlatformListener ?? registerPlatformConnectivityListener;
    _cancelPlatformListener = registrar(_handlePlatformStatusChanged);
  }

  final DateTime Function() _clock;

  ConnectivityStatus _status = ConnectivityStatus.unknown;
  DateTime? _lastReachableAt;
  DateTime? _lastFailureAt;
  String? _offlineReason;
  void Function()? _cancelPlatformListener;

  ConnectivityStatus get status => _status;

  bool get isOnline => _status == ConnectivityStatus.online;

  bool get isOffline => _status == ConnectivityStatus.offline;

  DateTime? get lastReachableAt => _lastReachableAt;

  DateTime? get lastFailureAt => _lastFailureAt;

  String? get offlineReason => _offlineReason;

  String get statusLabel {
    switch (_status) {
      case ConnectivityStatus.unknown:
        return 'Checking';
      case ConnectivityStatus.online:
        return 'Online';
      case ConnectivityStatus.offline:
        return 'Offline';
    }
  }

  String get statusMessage {
    switch (_status) {
      case ConnectivityStatus.unknown:
        return 'The app is still establishing whether the network is reachable.';
      case ConnectivityStatus.online:
        return _lastReachableAt == null
            ? 'Recent requests reached the backend successfully.'
            : 'Last confirmed backend reachability at ${_formatTimestamp(_lastReachableAt!)}.';
      case ConnectivityStatus.offline:
        return _offlineReason ??
            'Recent requests could not reach the backend. Reconnect to continue uploads and live refreshes.';
    }
  }

  void markReachable() {
    _lastReachableAt = _clock().toUtc();
    _offlineReason = null;
    _setStatus(ConnectivityStatus.online);
  }

  void markUnreachable([
    String reason =
        'Recent requests could not reach the backend. Reconnect to continue uploads and live refreshes.',
  ]) {
    _lastFailureAt = _clock().toUtc();
    _offlineReason = reason;
    _setStatus(ConnectivityStatus.offline);
  }

  void _handlePlatformStatusChanged(bool isOnline) {
    if (isOnline) {
      markReachable();
      return;
    }

    markUnreachable(
      'The device reported that the network is offline. Reconnect to continue uploads and live refreshes.',
    );
  }

  void _setStatus(ConnectivityStatus nextStatus) {
    if (_status == nextStatus) {
      notifyListeners();
      return;
    }

    _status = nextStatus;
    notifyListeners();
  }

  String _formatTimestamp(DateTime timestamp) {
    final local = timestamp.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$month/$day ${local.year} $hour:$minute';
  }

  @override
  void dispose() {
    _cancelPlatformListener?.call();
    _cancelPlatformListener = null;
    super.dispose();
  }
}
