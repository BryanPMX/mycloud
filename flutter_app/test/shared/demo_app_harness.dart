import 'package:familycloud/app.dart';
import 'package:familycloud/core/config/app_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

AppConfig demoAppConfig() {
  return AppConfig(
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
  );
}

Future<void> pumpDemoApp(
  WidgetTester tester, {
  Size size = const Size(500, 1600),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.pumpWidget(App(config: demoAppConfig()));
  await tester.pumpAndSettle();
}

Future<void> signInAsDemoMember(WidgetTester tester) {
  return signInToDemoWorkspace(
    tester,
    email: 'member@mynube.live',
    password: 'demo-password',
  );
}

Future<void> signInAsDemoAdmin(WidgetTester tester) {
  return signInToDemoWorkspace(
    tester,
    email: 'admin@mynube.live',
    password: 'demo-password',
  );
}

Future<void> signInToDemoWorkspace(
  WidgetTester tester, {
  required String email,
  required String password,
}) async {
  expect(find.text('Sign in to Mynube'), findsOneWidget);

  final emailField = find.byType(TextField).at(0);
  final passwordField = find.byType(TextField).at(1);
  await tester.enterText(emailField, email);
  await tester.enterText(passwordField, password);

  await tester.ensureVisible(find.text('Enter workspace'));
  await tester.tap(find.text('Enter workspace'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
}

Future<void> openSection(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label));
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}
