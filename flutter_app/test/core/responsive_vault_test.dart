import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../shared/demo_app_harness.dart';

void main() {
  for (final scenario in [
    (TargetPlatform.iOS, const Size(390, 844), Brightness.light),
    (TargetPlatform.android, const Size(360, 800), Brightness.dark),
    (TargetPlatform.macOS, const Size(1440, 1000), Brightness.light),
    (TargetPlatform.iOS, const Size(834, 1112), Brightness.dark),
    (TargetPlatform.android, const Size(320, 640), Brightness.light),
  ]) {
    testWidgets(
        'vault, circle and collections fit ${scenario.$1.name} ${scenario.$2} ${scenario.$3.name}',
        (tester) async {
      debugDefaultTargetPlatformOverride = scenario.$1;
      tester.platformDispatcher.platformBrightnessTestValue = scenario.$3;
      addTearDown(() {
        debugDefaultTargetPlatformOverride = null;
        tester.platformDispatcher.clearPlatformBrightnessTestValue();
      });
      try {
        await pumpDemoApp(tester, size: scenario.$2);
        await signInAsDemoMember(tester);
        expect(find.text('Your vault'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const ValueKey('open-upload')));
        await tester.pumpAndSettle();
        expect(find.text('Add memories'), findsWidgets);
        expect(tester.takeException(), isNull);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        await openSection(tester, 'Shared');
        expect(find.text('Your circle'), findsOneWidget);
        expect(find.text('Sofia'), findsWidgets);
        expect(tester.takeException(), isNull);
        await openSection(tester, 'Collections');
        expect(
            find.byKey(const ValueKey('create-album-button')), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        debugDefaultTargetPlatformOverride = null;
        tester.platformDispatcher.clearPlatformBrightnessTestValue();
      }
    });
  }
  testWidgets('large text and reduced motion keep the compact vault usable',
      (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    try {
      await pumpDemoApp(tester, size: const Size(390, 844));
      await signInAsDemoMember(tester);
      expect(find.text('Your vault'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await openSection(tester, 'Shared');
      expect(tester.takeException(), isNull);
      await openSection(tester, 'Collections');
      expect(tester.takeException(), isNull);
    } finally {
      tester.platformDispatcher.clearTextScaleFactorTestValue();
      tester.platformDispatcher.clearAccessibilityFeaturesTestValue();
    }
  });
}
