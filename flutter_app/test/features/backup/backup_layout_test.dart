import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:familycloud/core/theme/app_theme.dart';
import 'package:familycloud/features/backup/data/backup_preferences_store.dart';
import 'package:familycloud/features/backup/providers/device_backup_provider.dart';
import 'package:familycloud/features/backup/ui/backup_settings_card.dart';
import '../../shared/fake_photo_library.dart';
import '../../shared/transfer_harness.dart';

void main() {
  for (final size in [
    const Size(320, 640),
    const Size(390, 844),
    const Size(1440, 900)
  ]) {
    testWidgets('backup choices fit $size and require explicit album consent',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final h = TransferHarness();
      final library = FakeLibrary();
      final provider = DeviceBackupProvider(
          auth: h.auth,
          uploads: h.uploads,
          library: library,
          store: MemoryBackupPreferencesStore(),
          available: true);
      await provider.initialize();
      addTearDown(() {
        provider.dispose();
        h.dispose();
      });
      await tester.pumpWidget(MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
              body: SingleChildScrollView(
                  child: BackupSettingsCard(provider: provider)))));
      expect(find.text('Backup off'), findsOneWidget);
      expect(library.permissionCalls, 0);
      await tester.ensureVisible(find.text('Choose backup albums'));
      await tester.tap(find.text('Choose backup albums'));
      await tester.pumpAndSettle();
      expect(find.text('Choose your backup'), findsOneWidget);
      expect(find.text('Camera'), findsOneWidget);
      expect(find.text('Wi-Fi only'), findsOneWidget);
      expect(provider.preferences.enabled, isFalse);
      await tester.ensureVisible(find.text('Save backup choices'));
      await tester.tap(find.text('Save backup choices'));
      await tester.pumpAndSettle();
      expect(provider.preferences.enabled, isFalse);
      expect(tester.takeException(), isNull);
    });
  }
}
