import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/shared/demo_app_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'demo admin happy path covers sign-in, library, albums, profile, and admin flows',
      (tester) async {
    await pumpDemoApp(tester, size: const Size(500, 1800));
    await signInAsDemoAdmin(tester);

    expect(find.text('Media library'), findsOneWidget);

    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('comment-input-media-1')),
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('comment-input-media-1')),
      'Integration test comment',
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('comment-submit-media-1')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Integration test comment'), findsOneWidget);

    await openSection(tester, 'Albums');
    await tester.tap(find.byKey(const ValueKey<String>('create-album-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey<String>('album-name-field')),
      'Integration Album',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('album-description-field')),
      'Created by integration coverage.',
    );
    await tester.tap(find.byKey(const ValueKey<String>('album-save-button')));
    await tester.pumpAndSettle();
    expect(find.text('Integration Album'), findsOneWidget);

    await openSection(tester, 'Profile');
    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('profile-display-name-field')),
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('profile-display-name-field')),
      'Integration Admin',
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('profile-display-name-save')),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('profile-display-name-save')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Profile saved.'), findsOneWidget);

    await openSection(tester, 'Admin');
    await tester.enterText(
      find.byKey(const ValueKey<String>('admin-invite-email')),
      'integration@family.com',
    );
    await tester.tap(find.byKey(const ValueKey<String>('admin-invite-submit')));
    await tester.pumpAndSettle();
    expect(find.textContaining('https://mynube.live/accept?token=demo-'),
        findsOneWidget);
  });

  testWidgets(
      'demo member happy path covers album sharing and directory-backed recipients',
      (tester) async {
    await pumpDemoApp(tester);
    await signInAsDemoMember(tester);
    await openSection(tester, 'Albums');

    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('album-share-album-1')),
    );
    await tester.tap(find.byKey(const ValueKey<String>('album-share-album-1')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('album-share-recipient-album-1')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Admin Operator'), findsWidgets);
  });
}
