import 'package:familycloud/features/auth/domain/user.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../shared/demo_app_harness.dart';

void main() {
  for (final scenario in [
    (const Size(320, 640), 1.0),
    (const Size(390, 844), 1.0),
    (const Size(834, 1112), 1.0),
    (const Size(1512, 805), 1.0),
    (const Size(390, 844), 1.6),
  ]) {
    testWidgets(
        'Admin and its dialogs fit ${scenario.$1} at text scale ${scenario.$2}',
        (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = scenario.$2;
      addTearDown(
          () => tester.platformDispatcher.clearTextScaleFactorTestValue());
      await pumpDemoApp(tester, size: scenario.$1);
      await signInAsDemoAdmin(tester);
      await openSection(tester, 'Admin');
      expect(find.text('Your people'), findsOneWidget);
      expect(find.textContaining('POST /admin'), findsNothing);
      expect(find.textContaining('What Flutter'), findsNothing);
      expect(tester.takeException(), isNull);
      final search = find.byKey(const ValueKey('admin-search'));
      await tester.ensureVisible(search);
      await tester.enterText(search, 'member@');
      await tester.pumpAndSettle();
      final manage =
          find.byKey(const ValueKey('admin-user-manage-user-member'));
      expect(manage, findsOneWidget);
      expect(find.byKey(const ValueKey('admin-user-manage-user-admin')),
          findsNothing);
      await tester.ensureVisible(manage);
      await tester.tap(manage);
      await tester.pumpAndSettle();
      expect(find.text('Manage account'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('admin-open-invite')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('admin-invite-email')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });
  }

  testWidgets(
      'account editor validates storage and preserves self-access protection',
      (tester) async {
    await pumpDemoApp(tester, size: const Size(1440, 1000));
    await signInAsDemoAdmin(tester);
    await openSection(tester, 'Admin');
    final semantics = tester.ensureSemantics();
    try {
      await tester.pump();
      expect(find.bySemanticsLabel('Search by name or email'), findsOneWidget);
    } finally {
      semantics.dispose();
    }

    final manage = find.byKey(const ValueKey('admin-user-manage-user-member'));
    await tester.ensureVisible(manage);
    await tester.tap(manage);
    await tester.pumpAndSettle();
    final quota = find.byKey(const ValueKey('admin-user-quota-user-member'));
    final save = find.byKey(const ValueKey('admin-user-save-user-member'));
    await tester.enterText(quota, '5');
    await tester.pump();
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.text('Their memories need at least 12 GB.'), findsOneWidget);
    await tester.enterText(quota, '32');
    await tester.pump();
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.text('Manage account'), findsNothing);
    expect(find.text('12 GB of 32 GB used'), findsOneWidget);
    final selfManage =
        find.byKey(const ValueKey('admin-user-manage-user-admin'));
    await tester.ensureVisible(selfManage);
    await tester.tap(selfManage);
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<DropdownButtonFormField<UserRole>>(
                find.byKey(const ValueKey('admin-user-role-user-admin')))
            .onChanged,
        isNull);
    expect(
        tester
            .widget<SwitchListTile>(
                find.byKey(const ValueKey('admin-user-active-user-admin')))
            .onChanged,
        isNull);
    expect(tester.takeException(), isNull);
  });
}
