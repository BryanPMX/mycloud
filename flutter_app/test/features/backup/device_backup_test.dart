import 'dart:async';
import 'dart:typed_data';
import 'package:familycloud/features/backup/data/backup_preferences_store.dart';
import 'package:familycloud/features/backup/domain/backup_preferences.dart';
import 'package:familycloud/features/backup/domain/photo_library.dart';
import 'package:familycloud/features/backup/providers/device_backup_provider.dart';
import 'package:familycloud/features/media/data/selected_upload_file.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../shared/memory_selected_upload_file.dart';
import '../../shared/transfer_harness.dart';
import '../../shared/fake_photo_library.dart';

void main() {
  late TransferHarness h;
  late FakeLibrary library;
  late DeviceBackupProvider backup;
  late MemoryBackupPreferencesStore store;
  setUp(() async {
    h = TransferHarness();
    library = FakeLibrary();
    store = MemoryBackupPreferencesStore();
    backup = DeviceBackupProvider(
        auth: h.auth,
        uploads: h.uploads,
        library: library,
        store: store,
        available: true,
        clock: () => DateTime.utc(2026, 11, 23));
    await backup.initialize();
  });
  tearDown(() {
    backup.dispose();
    h.dispose();
  });
  SelectedUploadFile file() => MemorySelectedUploadFile(
      name: 'synthetic.png',
      mimeType: 'image/png',
      bytes: Uint8List.fromList([1, 2, 3]));
  DevicePhoto photo(
          {String key = 'same-photo',
          DateTime? captured,
          Future<SelectedUploadFile?> Function()? open}) =>
      DevicePhoto(
          key: key,
          createdAt: captured ?? DateTime.utc(2026, 11, 24),
          isVideo: false,
          open: open ?? () async => file());
  test('off by default performs no Photos access or API requests', () async {
    expect(backup.preferences.enabled, isFalse);
    expect(library.permissionCalls, 0);
    expect(h.requests, isEmpty);
    await backup.scan();
    expect(library.pageCalls, 0);
  });
  test('overlapping selected albums enqueue one source only', () async {
    library.photos = [photo()];
    await backup.chooseAccess();
    await backup.update(const BackupPreferences(
        enabled: true, albumIds: {'a', 'b'}, includeExisting: true));
    expect(h.uploads.tasks, hasLength(1));
  });
  test('Wi-Fi constraint prevents even exporting phone originals', () async {
    library.online = false;
    library.photos = [
      photo(open: () async {
        fail('Must not export while waiting for Wi-Fi');
      })
    ];
    await backup.chooseAccess();
    await backup
        .update(const BackupPreferences(enabled: true, albumIds: {'a'}));
    expect(library.pageCalls, 0);
    expect(h.requests, isEmpty);
    expect(backup.message, contains('Wi-Fi'));
  });
  test('existing photos require an explicit opt-in', () async {
    library.photos = [photo(captured: DateTime.utc(2020))];
    await backup.chooseAccess();
    await backup
        .update(const BackupPreferences(enabled: true, albumIds: {'a'}));
    expect(h.uploads.tasks, isEmpty);
    await backup.update(backup.preferences.copyWith(includeExisting: true));
    expect(h.uploads.tasks, hasLength(1));
  });
  test('turning off during export prevents the late upload', () async {
    final started = Completer<void>();
    final exported = Completer<SelectedUploadFile?>();
    library.photos = [
      photo(open: () {
        started.complete();
        return exported.future;
      })
    ];
    await backup.chooseAccess();
    final enabling =
        backup.update(const BackupPreferences(enabled: true, albumIds: {'a'}));
    await started.future;
    await backup.update(backup.preferences.copyWith(enabled: false));
    exported.complete(file());
    await enabling;
    expect(backup.preferences.enabled, isFalse);
    expect(h.uploads.tasks, isEmpty);
    expect(h.requests, isEmpty);
  });
  test('permission reduction stops discovery until access is reviewed',
      () async {
    await backup.chooseAccess();
    await backup
        .update(const BackupPreferences(enabled: true, albumIds: {'a'}));
    final previous = library.pageCalls;
    library.access = PhotoAccess.limited;
    library.photos = [photo()];
    await backup.scan();
    expect(library.pageCalls, previous);
    expect(h.requests, isEmpty);
    expect(backup.message, contains('access changed'));
  });
  test('limited Photos exposes only an explicitly permitted scope', () async {
    library.access = PhotoAccess.limited;
    await backup.chooseAccess();
    expect(backup.albums.map((a) => a.id), ['__allowed__']);
    await backup
        .update(const BackupPreferences(enabled: true, albumIds: {'a'}));
    expect(backup.preferences.enabled, isFalse);
    expect(h.requests, isEmpty);
  });
  test('expanding Photos access cannot silently expand the backup selection',
      () async {
    library.access = PhotoAccess.limited;
    await backup.chooseAccess();
    await backup.update(
        const BackupPreferences(enabled: true, albumIds: {'__allowed__'}));
    final previous = library.pageCalls;
    library.access = PhotoAccess.full;
    library.photos = [photo()];
    await backup.chooseAccess();
    await backup.scan();
    expect(library.pageCalls, previous);
    expect(h.requests, isEmpty);
    expect(backup.message, contains('access changed'));
    await backup.update(backup.preferences.copyWith(albumIds: {'a'}));
    expect(h.uploads.tasks, hasLength(1));
  });
  test('saving disabled choices does not establish a capture cutoff', () async {
    await backup.chooseAccess();
    await backup.update(const BackupPreferences(albumIds: {'a'}));
    expect(backup.preferences.startedAt, isNull);
    await backup.update(backup.preferences.copyWith(enabled: true));
    expect(backup.preferences.startedAt, DateTime.utc(2026, 11, 23));
  });
  test('returning to an account after switching requires renewed consent',
      () async {
    await backup.chooseAccess();
    await backup
        .update(const BackupPreferences(enabled: true, albumIds: {'a'}));
    h.uploads.reset();
    h.auth.updateCurrentUser(transferUser('second'));
    await backup.initialize();
    h.uploads.reset();
    h.auth.updateCurrentUser(transferUser('first'));
    await backup.initialize();
    expect(backup.preferences.enabled, isFalse);
    expect((await store.read('first')).enabled, isFalse);
  });
  test('account switch cannot assign an in-progress export to the new vault',
      () async {
    final started = Completer<void>();
    final exported = Completer<SelectedUploadFile?>();
    library.photos = [
      photo(open: () {
        started.complete();
        return exported.future;
      })
    ];
    await backup.chooseAccess();
    final enabling =
        backup.update(const BackupPreferences(enabled: true, albumIds: {'a'}));
    await started.future;
    h.uploads.reset();
    h.auth.updateCurrentUser(transferUser('second'));
    exported.complete(file());
    await enabling;
    expect(h.uploads.tasks, isEmpty);
    expect(h.requests, isEmpty);
    expect(backup.preferences.enabled, isFalse);
  });
}
