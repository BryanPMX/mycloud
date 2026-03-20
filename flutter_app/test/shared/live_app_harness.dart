import 'dart:convert';

import 'package:familycloud/app.dart';
import 'package:familycloud/core/config/app_config.dart';
import 'package:familycloud/features/media/data/upload_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'memory_selected_upload_file.dart';

const String liveIntegrationEmail = String.fromEnvironment(
  'ITEST_LIVE_EMAIL',
  defaultValue: '',
);
const String liveIntegrationPassword = String.fromEnvironment(
  'ITEST_LIVE_PASSWORD',
  defaultValue: '',
);

bool get isLiveIntegrationConfigured =>
    liveIntegrationEmail.trim().isNotEmpty &&
    liveIntegrationPassword.trim().isNotEmpty;

AppConfig liveAppConfig() => AppConfig.fromEnvironment();

Future<AppController> pumpLiveApp(
  WidgetTester tester, {
  UploadFilesPicker? uploadFilesPicker,
}) async {
  final controller = AppController();
  await tester.pumpWidget(
    App(
      config: liveAppConfig(),
      controller: controller,
      uploadFilesPicker: uploadFilesPicker,
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}

Future<void> signInToLiveWorkspace(
  WidgetTester tester, {
  required String email,
  required String password,
}) async {
  expect(find.text('Sign in to Mynube'), findsOneWidget);

  await tester.enterText(
    find.byKey(const ValueKey<String>('login-email')),
    email,
  );
  await tester.enterText(
    find.byKey(const ValueKey<String>('login-password')),
    password,
  );
  await tester.tap(find.byKey(const ValueKey<String>('login-submit')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
}

UploadFilesPicker buildLiveUploadPicker() {
  final bytes = Uint8List.fromList(
    base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO3Zqz8AAAAASUVORK5CYII=',
    ),
  );

  return () async => <MemorySelectedUploadFile>[
        MemorySelectedUploadFile(
          name: 'live-integration-upload.png',
          mimeType: 'image/png',
          bytes: bytes,
        ),
      ];
}
