import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/shared/live_app_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'live backend upload path can enqueue a device file and reconnect worker progress',
    (tester) async {
      final controller = await pumpLiveApp(
        tester,
        uploadFilesPicker: buildLiveUploadPicker(),
      );

      await signInToLiveWorkspace(
        tester,
        email: liveIntegrationEmail,
        password: liveIntegrationPassword,
      );

      expect(find.byKey(const ValueKey<String>('photo-grid-screen')),
          findsOneWidget);
      expect(controller.mediaUploadProvider, isNotNull);
      expect(controller.uploadProgressHub, isNotNull);

      await tester
          .tap(find.byKey(const ValueKey<String>('media-upload-start')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(controller.mediaUploadProvider!.tasks, isNotEmpty);
      expect(
        controller.mediaUploadProvider!.tasks.first.filename,
        'live-integration-upload.png',
      );

      await controller.uploadProgressHub!.simulateConnectionDrop();
      await tester.pump();
      expect(
        controller.uploadProgressHub!.statusLabel,
        'Reconnecting',
      );

      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      expect(
        controller.uploadProgressHub!.statusLabel,
        anyOf('Live', 'Reconnecting'),
      );
    },
    skip: !isLiveIntegrationConfigured,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
