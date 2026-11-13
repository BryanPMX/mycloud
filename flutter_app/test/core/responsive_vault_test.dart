import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../shared/demo_app_harness.dart';
import 'package:familycloud/core/theme/app_theme.dart';
import 'package:familycloud/shared/widgets/vault_ui.dart';

void main() {
  for (final scenario in [
    (TargetPlatform.iOS, const Size(390, 844), Brightness.light),
    (TargetPlatform.android, const Size(360, 800), Brightness.dark),
    (TargetPlatform.macOS, const Size(1440, 1000), Brightness.light),
    (TargetPlatform.macOS, const Size(1512, 805), Brightness.dark),
    (TargetPlatform.windows, const Size(1920, 1080), Brightness.dark),
    (TargetPlatform.windows, const Size(1024, 768), Brightness.light),
    (TargetPlatform.iOS, const Size(834, 1112), Brightness.dark),
    (TargetPlatform.android, const Size(320, 640), Brightness.light),
  ]) {
    testWidgets(
        'vault, circle, collections and profile fit ${scenario.$1.name} ${scenario.$2} ${scenario.$3.name}',
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
        final gallery =
            tester.getRect(find.byKey(const ValueKey('vault-gallery')));
        final search =
            tester.getRect(find.byKey(const ValueKey('vault-search')));
        expect(gallery.left, tester.getRect(find.byType(VaultPill).first).left);
        expect(gallery.right, search.right);
        expect(gallery.left,
            tester.getRect(find.byKey(const ValueKey('section-title'))).left);
        if (gallery.width < 800) expect(gallery.left, search.left);
        final titleRect =
            tester.getRect(find.byKey(const ValueKey('section-title')));
        final dividerRect =
            tester.getRect(find.byKey(const ValueKey('section-divider')));
        void expectMatchingSection() {
          final title =
              tester.getRect(find.byKey(const ValueKey('section-title')));
          final divider =
              tester.getRect(find.byKey(const ValueKey('section-divider')));
          expect(title.left, titleRect.left);
          expect(divider.left, dividerRect.left);
          expect(divider.right, dividerRect.right);
          // Allow natural text wrapping on compact screens.
          if (scenario.$2.width >= 600) {
            expect(title.top, titleRect.top);
            expect(divider.top, dividerRect.top);
          }
        }

        await tester.drag(find.byKey(const ValueKey('vault-content-scroll')),
            const Offset(0, -180));
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(find.byKey(const ValueKey('section-title'))),
            titleRect.topLeft);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const ValueKey('open-upload')));
        await tester.pumpAndSettle();
        expect(find.text('Add memories'), findsWidgets);
        expect(tester.takeException(), isNull);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        await openSection(tester, 'Shared');
        expect(find.text('Your circle'), findsOneWidget);
        expectMatchingSection();
        expect(find.text('Sofia'), findsWidgets);
        expect(tester.takeException(), isNull);
        await openSection(tester, 'Collections');
        expect(
            find.byKey(const ValueKey('create-album-button')), findsOneWidget);
        expectMatchingSection();
        expect(tester.takeException(), isNull);
        await openSection(tester, 'Profile');
        expect(find.text('Make it yours.'), findsOneWidget);
        expect(tester.takeException(), isNull);
        if (scenario.$2.width >= 1200) {
          final nameCard =
              tester.getRect(find.byKey(const ValueKey('profile-name-card')));
          final storageCard = tester
              .getRect(find.byKey(const ValueKey('profile-storage-card')));
          expect(nameCard.top, closeTo(storageCard.top, 1));
          expect(nameCard.bottom, closeTo(storageCard.bottom, 1));
        }
      } finally {
        debugDefaultTargetPlatformOverride = null;
        tester.platformDispatcher.clearPlatformBrightnessTestValue();
      }
    });
  }
  testWidgets(
      'empty sections remain usable in a short viewport with large text',
      (tester) async {
    tester.view.physicalSize = const Size(390, 480);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
    var activated = false;
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
            body: Padding(
                padding: const EdgeInsets.all(18),
                child: VaultSection(
                    eyebrow: 'Keep the good things together',
                    title: 'Collections',
                    subtitle: 'Little worlds, made by you.',
                    toolbar: const SizedBox(height: 48),
                    child: VaultSectionBody(
                        center: true,
                        child: VaultEmptyState(
                            icon: Icons.bookmarks_outlined,
                            title: 'Your stories, kept together.',
                            message:
                                'Gather a few favorites into your first collection.',
                            action: OutlinedButton(
                                onPressed: () => activated = true,
                                child: const Text(
                                    'Create your first collection')))))))));
    await tester.pumpAndSettle();
    final titlePosition =
        tester.getTopLeft(find.byKey(const ValueKey('section-title')));
    await tester.ensureVisible(find.text('Create your first collection'));
    await tester.tap(find.text('Create your first collection'));
    expect(activated, isTrue);
    expect(tester.getTopLeft(find.byKey(const ValueKey('section-title'))),
        titlePosition);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an empty search keeps the search control available',
      (tester) async {
    await pumpDemoApp(tester, size: const Size(390, 844));
    await signInAsDemoMember(tester);
    await tester.enterText(find.byKey(const ValueKey('vault-search')),
        'no matching memory fixture');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(find.text('Nothing here just yet.'), findsOneWidget);
    expect(find.byKey(const ValueKey('vault-search')), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('vault-search')), '');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(find.text('9 memories'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

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
      await openSection(tester, 'Profile');
      expect(find.text('Make it yours.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      tester.platformDispatcher.clearTextScaleFactorTestValue();
      tester.platformDispatcher.clearAccessibilityFeaturesTestValue();
    }
  });
}
