import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../shared/demo_app_harness.dart';

void main() {
  testWidgets(
      'non-admin album owners can open share dialog and pick directory recipients',
      (tester) async {
    await pumpDemoApp(tester);
    await signInAsDemoMember(tester);
    await openSection(tester, 'Albums');
    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('album-share-album-1')),
    );
    await tester.tap(find.byKey(const ValueKey<String>('album-share-album-1')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('album-share-recipient-album-1')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('album-share-recipient-album-1')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Admin Operator'), findsWidgets);
  });

  testWidgets(
      'boots, signs in, and exercises profile, album, and admin mutations',
      (tester) async {
    await pumpDemoApp(tester, size: const Size(500, 1800));
    await signInAsDemoAdmin(tester);

    expect(find.text('Media library'), findsOneWidget);

    await tester.ensureVisible(
        find.byKey(const ValueKey<String>('comment-input-media-1')));
    await tester.enterText(
      find.byKey(const ValueKey<String>('comment-input-media-1')),
      'Smoke test comment',
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('comment-submit-media-1')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Smoke test comment'), findsOneWidget);

    await openSection(tester, 'Albums');

    expect(find.text('Live album workspace'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('create-album-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey<String>('album-name-field')),
      'Smoke Test Album',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('album-description-field')),
      'Created during widget coverage.',
    );
    await tester.tap(find.byKey(const ValueKey<String>('album-save-button')));
    await tester.pumpAndSettle();

    expect(find.text('Smoke Test Album'), findsOneWidget);

    await openSection(tester, 'Profile');

    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('profile-display-name-field')),
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('profile-display-name-field')),
      'Demo Admin Updated',
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('profile-display-name-save')),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('profile-display-name-save')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Profile saved.'), findsOneWidget);
    expect(find.text('Demo Admin Updated'), findsWidgets);

    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('profile-avatar-upload')),
    );
    await tester
        .tap(find.byKey(const ValueKey<String>('profile-avatar-upload')));
    await tester.pumpAndSettle();

    expect(find.text('Avatar saved.'), findsOneWidget);

    await openSection(tester, 'Admin');
    await tester.enterText(
      find.byKey(const ValueKey<String>('admin-invite-email')),
      'fresh@family.com',
    );
    await tester.tap(find.byKey(const ValueKey<String>('admin-invite-submit')));
    await tester.pumpAndSettle();

    expect(find.textContaining('https://mynube.live/accept?token=demo-'),
        findsOneWidget);
  });
}
