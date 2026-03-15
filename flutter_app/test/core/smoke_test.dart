import 'package:familycloud/app.dart';
import 'package:familycloud/core/config/app_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('boots, signs in, and navigates to albums', (tester) async {
    tester.view.physicalSize = const Size(500, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      App(
        config: AppConfig(
          appName: 'Mynube',
          appBaseUri: Uri(scheme: 'https', host: 'mynube.live'),
          apiBaseUri: Uri(
            scheme: 'https',
            host: 'api.mynube.live',
            path: '/api/v1',
          ),
          websocketUri: Uri(
            scheme: 'wss',
            host: 'api.mynube.live',
            path: '/ws/progress',
          ),
          environmentLabel: 'test',
          useDemoData: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sign in to Mynube'), findsOneWidget);

    final emailField = find.byType(TextField).at(0);
    final passwordField = find.byType(TextField).at(1);
    await tester.enterText(emailField, 'admin@mynube.live');
    await tester.enterText(passwordField, 'demo-password');

    await tester.ensureVisible(find.text('Enter workspace'));
    await tester.tap(find.text('Enter workspace'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.text('Media library'), findsOneWidget);

    await tester.tap(find.text('Albums'));
    await tester.pumpAndSettle();

    expect(find.text('Live album lists'), findsOneWidget);
  });
}
