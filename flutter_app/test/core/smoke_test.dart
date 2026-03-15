import 'package:familycloud/app.dart';
import 'package:familycloud/core/config/app_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
      'non-admin album owners can open share dialog and pick directory recipients',
      (tester) async {
    tester.view.physicalSize = const Size(500, 1600);
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

    await tester.enterText(find.byType(TextField).at(0), 'member@mynube.live');
    await tester.enterText(find.byType(TextField).at(1), 'demo-password');
    await tester.tap(find.text('Enter workspace'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Albums'));
    await tester.pumpAndSettle();
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

    await tester.tap(find.text('Albums'));
    await tester.pumpAndSettle();

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

    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();

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

    await tester.tap(find.text('Admin'));
    await tester.pumpAndSettle();
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
