import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../domain/backup_preferences.dart';

abstract interface class BackupPreferencesStore {
  Future<BackupPreferences> read(String ownerId);
  Future<void> save(String ownerId, BackupPreferences preferences);
}

class SecureBackupPreferencesStore implements BackupPreferencesStore {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  String _key(String ownerId) =>
      'mynube.backup.v1.${base64Url.encode(utf8.encode(ownerId))}';
  @override
  Future<BackupPreferences> read(String ownerId) async {
    final raw = await _storage.read(key: _key(ownerId));
    return raw == null
        ? const BackupPreferences()
        : BackupPreferences.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  @override
  Future<void> save(String ownerId, BackupPreferences preferences) => _storage
      .write(key: _key(ownerId), value: jsonEncode(preferences.toJson()));
}

class MemoryBackupPreferencesStore implements BackupPreferencesStore {
  final Map<String, BackupPreferences> values = {};
  @override
  Future<BackupPreferences> read(String ownerId) async =>
      values[ownerId] ?? const BackupPreferences();
  @override
  Future<void> save(String ownerId, BackupPreferences preferences) async {
    values[ownerId] = preferences;
  }
}
