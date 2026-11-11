import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../shared/demo_app_harness.dart';

void main() {
  testWidgets('a cold invitation link opens with its private fragment token',
      (tester) async {
    tester.binding.platformDispatcher.defaultRouteNameTestValue =
        '/accept#private-invitation-fixture';
    addTearDown(
        tester.binding.platformDispatcher.clearDefaultRouteNameTestValue);
    await pumpDemoApp(tester);

    expect(find.text('Welcome to Mynube'), findsOneWidget);
    final code = tester.widget<TextField>(find.byWidgetPredicate((widget) =>
        widget is TextField &&
        widget.decoration?.labelText == 'Invitation code'));
    expect(code.controller?.text, 'private-invitation-fixture');
  });

  for (final route in ['/profile', '/#/profile']) {
    testWidgets('a cold $route link resumes Profile after sign in',
        (tester) async {
      tester.binding.platformDispatcher.defaultRouteNameTestValue = route;
      addTearDown(
          tester.binding.platformDispatcher.clearDefaultRouteNameTestValue);
      await pumpDemoApp(tester);
      await signInAsDemoMember(tester);

      expect(find.text('Make it yours.'), findsOneWidget);
    });
  }
}
