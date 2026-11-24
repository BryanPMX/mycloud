// Isolated design preview. Never reads device Photos, auth tokens or live APIs.
import 'package:flutter/material.dart';
import 'package:familycloud/core/theme/app_theme.dart';
import 'package:familycloud/features/backup/data/backup_preferences_store.dart';
import 'package:familycloud/features/backup/providers/device_backup_provider.dart';
import 'package:familycloud/features/backup/ui/backup_settings_card.dart';
import '../shared/fake_photo_library.dart';
import '../shared/transfer_harness.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final harness = TransferHarness();
  final library = FakeLibrary();
  final backup = DeviceBackupProvider(
      auth: harness.auth,
      uploads: harness.uploads,
      library: library,
      store: MemoryBackupPreferencesStore(),
      available: true);
  await backup.initialize();
  runApp(MaterialApp(
      title: 'Mynube backup preview',
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.dark,
      home: Scaffold(
          body: SafeArea(
              child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                      child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 900),
                          child: Column(children: [
                            const SizedBox(height: 24),
                            const Text('MYNUBE • SAMPLE PREVIEW'),
                            const SizedBox(height: 12),
                            const Text('Your memories, your choices.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    fontSize: 30, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 12),
                            const Text(
                                'No device access. No real uploads. Sample albums only.',
                                textAlign: TextAlign.center),
                            const SizedBox(height: 28),
                            BackupSettingsCard(provider: backup),
                          ]))))))));
}
