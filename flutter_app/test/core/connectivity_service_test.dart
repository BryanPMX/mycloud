import 'package:familycloud/core/connectivity/connectivity_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('markReachable and markUnreachable update status and timestamps', () {
    final onlineInstant = DateTime.utc(2026, 3, 15, 10, 0);
    final offlineInstant = DateTime.utc(2026, 3, 15, 10, 5);
    var clock = onlineInstant;

    final service = ConnectivityService(
      clock: () => clock,
      registerPlatformListener: (_) => null,
    );

    expect(service.status, ConnectivityStatus.unknown);

    service.markReachable();
    expect(service.status, ConnectivityStatus.online);
    expect(service.lastReachableAt, onlineInstant);
    expect(service.isOffline, isFalse);

    clock = offlineInstant;
    service.markUnreachable('API timeout');
    expect(service.status, ConnectivityStatus.offline);
    expect(service.lastFailureAt, offlineInstant);
    expect(service.offlineReason, 'API timeout');
    expect(service.isOffline, isTrue);
  });

  test('platform listener transitions the service automatically', () {
    late void Function(bool isOnline) capturedListener;

    final service = ConnectivityService(
      initialPlatformOnline: false,
      registerPlatformListener: (listener) {
        capturedListener = listener;
        return null;
      },
    );

    expect(service.status, ConnectivityStatus.offline);

    capturedListener(true);
    expect(service.status, ConnectivityStatus.online);

    capturedListener(false);
    expect(service.status, ConnectivityStatus.offline);
    expect(
      service.statusMessage,
      contains('device reported that the network is offline'),
    );
  });
}
