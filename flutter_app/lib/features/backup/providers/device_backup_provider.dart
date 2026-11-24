import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../auth/providers/auth_provider.dart';
import '../../media/providers/media_upload_provider.dart';
import '../data/backup_preferences_store.dart';
import '../domain/backup_preferences.dart';
import '../domain/photo_library.dart';

/// Coordinates consent and discovery. All bytes use the normal owned uploader.
class DeviceBackupProvider extends ChangeNotifier {
  DeviceBackupProvider(
      {required this.auth,
      required this.uploads,
      required this.library,
      required this.store,
      this.available = false,
      DateTime Function()? clock})
      : _clock = clock ?? DateTime.now {
    auth.addListener(_authChanged);
  }
  final AuthProvider auth;
  final MediaUploadProvider uploads;
  final PhotoLibrary library;
  final BackupPreferencesStore store;
  final bool available;
  final DateTime Function() _clock;
  BackupPreferences _preferences = const BackupPreferences();
  BackupPreferences get preferences => _preferences;
  List<DeviceAlbum> _albums = [];
  List<DeviceAlbum> get albums => List.unmodifiable(_albums);
  PhotoAccess _access = PhotoAccess.denied;
  PhotoAccess get access => _access;
  String? _message;
  String? get message => _message;
  bool _busy = false;
  bool get busy => _busy;
  bool _disposed = false;
  bool _foreground = true;
  String? _owner;
  int _generation = 0;
  final Map<String, int> _pages = {};
  int _albumRotation = 0;
  Timer? _timer;
  Future<void>? _loadFuture;
  bool _newLogin = false;
  bool _accessNeedsReview = false;

  bool get supported => available && library.supported && !auth.usesDemoData;
  bool _current(int generation, String owner) =>
      !_disposed && generation == _generation && owner == auth.currentUser?.id;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _authChanged() {
    if (auth.status == AuthStatus.signingIn) {
      _newLogin = true;
      return;
    }
    final owner = auth.currentUser?.id;
    final forceOff =
        _newLogin || (_owner != null && owner != null && _owner != owner);
    if (_owner == owner && !forceOff) return;
    if (owner != null) _newLogin = false;
    final old = _owner;
    _owner = owner;
    final generation = ++_generation;
    _preferences = const BackupPreferences();
    _albums = [];
    _pages.clear();
    _busy = false;
    _accessNeedsReview = false;
    _message = null;
    _timer?.cancel();
    unawaited(library.stopObserving());
    if (old != null && supported) {
      unawaited(store
          .read(old)
          .then((p) => store.save(old, p.copyWith(enabled: false)))
          .catchError((_) {}));
    }
    _notify();
    _loadFuture = null;
    if (owner != null && supported) {
      _loadFuture = _load(owner, generation, forceOff: forceOff);
      unawaited(_loadFuture);
    }
  }

  Future<void> initialize() async {
    if (_owner != auth.currentUser?.id) _authChanged();
    await _loadFuture;
  }

  Future<void> _load(String owner, int generation,
      {bool forceOff = false}) async {
    try {
      var saved = await store.read(owner);
      if (forceOff) {
        saved = saved.copyWith(enabled: false);
        await store.save(owner, saved);
      }
      await uploads.restorePendingUploads();
      if (!_current(generation, owner)) return;
      _preferences = saved;
      if (!saved.enabled) {
        _notify();
        return;
      }
      _access = await library.permission();
      if (!_current(generation, owner)) return;
      if (_access != PhotoAccess.denied) _albums = await library.albums();
      if (!_current(generation, owner)) return;
      _notify();
      if (saved.enabled) {
        await _watch();
        await scan();
      }
    } catch (_) {
      if (!_current(generation, owner)) return;
      _message =
          'Backup settings need attention. Automatic backup is off until you review them.';
      _preferences = const BackupPreferences();
      _notify();
    }
  }

  /// Permission prompts only follow a deliberate user action in this screen.
  Future<void> chooseAccess() async {
    if (!supported || _busy) return;
    final owner = _owner;
    final generation = _generation;
    if (owner == null) return;
    _busy = true;
    _message = null;
    _notify();
    try {
      final access = await library.permission(request: true);
      if (!_current(generation, owner)) return;
      final albums = access == PhotoAccess.denied
          ? <DeviceAlbum>[]
          : await library.albums();
      if (!_current(generation, owner)) return;
      if (_preferences.enabled && access != _access) {
        _accessNeedsReview = true;
        uploads.pauseAutomaticBackups();
      }
      _access = access;
      _albums = albums;
      if (access == PhotoAccess.denied) {
        _message = 'Photos access is off. You can still add memories manually.';
      }
    } catch (_) {
      if (_current(generation, owner)) {
        _message = 'Couldn’t open Photos. Please try again.';
      }
    } finally {
      if (_current(generation, owner)) {
        _busy = false;
        _notify();
      }
    }
  }

  Future<void> update(BackupPreferences preferences) async {
    if (!supported || (_busy && preferences.enabled) || _owner == null) return;
    if (preferences.albumIds.length > 20) {
      _message = 'Choose up to 20 albums for this device.';
      _notify();
      return;
    }
    if (preferences.enabled &&
        (preferences.albumIds.isEmpty || _access == PhotoAccess.denied)) {
      _message =
          'Choose Photos access and at least one album before turning on backup.';
      _notify();
      return;
    }
    final owner = _owner!;
    final generation = ++_generation;
    _busy = false;
    if (!preferences.enabled) {
      _preferences = preferences;
      _timer?.cancel();
      uploads.pauseAutomaticBackups();
    }
    // A second user action is required after permission/album changes; no silent
    // expansion from limited Photos access to an entire device library.
    final known = _albums.map((a) => a.id).toSet();
    if (preferences.enabled && !known.containsAll(preferences.albumIds)) {
      _message =
          'Your available albums changed. Review the selection before continuing.';
      _notify();
      return;
    }
    final next = preferences.copyWith(
        startedAt: preferences.startedAt ??
            (preferences.enabled ? _clock().toUtc() : null));
    try {
      await store.save(owner, next);
      if (!_current(generation, owner)) return;
      await uploads.updateAutomaticBackupPolicy(next.wifiOnly);
      if (!_current(generation, owner)) return;
      _preferences = next;
      _accessNeedsReview = false;
      _pages.clear();
      _message = null;
      _timer?.cancel();
      await library.stopObserving();
      if (!_current(generation, owner)) return;
      if (next.enabled) {
        await _watch();
        await scan();
      }
      _notify();
    } catch (_) {
      if (_current(generation, owner)) {
        _message = 'Couldn’t save backup settings. Please try again.';
        _notify();
      }
    }
  }

  Future<void> _watch() async {
    await library.observe(() => unawaited(scan()));
    _timer?.cancel();
    // Discovery runs while this app is active. Native transfers already queued
    // may continue when suspended; this is not an iOS background library daemon.
    _timer =
        Timer.periodic(const Duration(seconds: 30), (_) => unawaited(scan()));
  }

  void setForeground(bool active) {
    _foreground = active;
    if (active) unawaited(scan());
  }

  Future<void> scan() async {
    if (!supported ||
        !_foreground ||
        _busy ||
        !_preferences.enabled ||
        _owner == null) {
      return;
    }
    final owner = _owner!;
    final generation = _generation;
    _busy = true;
    _message = 'Checking your selected albums…';
    _notify();
    var queued = 0;
    var skipped = 0;
    try {
      await uploads.restorePendingUploads();
      if (!_current(generation, owner)) return;
      if (!uploads.recoveryReady) {
        _message = 'Review your saved uploads before starting another backup.';
        return;
      }
      if (!await library.canTransfer(wifiOnly: _preferences.wifiOnly)) {
        _message = _preferences.wifiOnly
            ? 'Waiting for Wi-Fi. Your backup settings are saved.'
            : 'Waiting for a connection.';
        return;
      }
      final access = await library.permission();
      if (!_current(generation, owner)) return;
      if (_accessNeedsReview ||
          access != _access ||
          access == PhotoAccess.denied ||
          !_albums
              .map((a) => a.id)
              .toSet()
              .containsAll(_preferences.albumIds)) {
        uploads.pauseAutomaticBackups();
        _message =
            'Photos access changed. Review access and album selection to continue.';
        return;
      }
      await uploads.resumeAutomaticBackups();
      await uploads.reconcileProcessing();
      if (!_current(generation, owner)) return;
      final sorted = _preferences.albumIds.toList()..sort();
      final offset = sorted.isEmpty ? 0 : _albumRotation++ % sorted.length;
      final selected = [...sorted.skip(offset), ...sorted.take(offset)];
      for (final album in selected.take(5)) {
        if (!_current(generation, owner) ||
            !_preferences.enabled ||
            !_foreground) {
          return;
        }
        final page = _pages[album] ?? 0;
        final photos = await library.page(album, page, 50);
        if (!_current(generation, owner)) return;
        var wholePage = true;
        for (final photo in photos) {
          if (!_current(generation, owner) ||
              !_preferences.enabled ||
              !_foreground) {
            return;
          }
          if (!photo.supported) {
            skipped++;
            continue;
          }
          if ((!_preferences.includeVideos && photo.isVideo) ||
              (!_preferences.includeExisting &&
                  photo.createdAt.isBefore(_preferences.startedAt!)) ||
              uploads.hasSource(photo.key)) {
            continue;
          }
          final file = await photo.open().timeout(const Duration(seconds: 60));
          if (!_current(generation, owner) ||
              !_preferences.enabled ||
              !_foreground) {
            return;
          }
          if (file == null) {
            skipped++;
            continue;
          }
          final accepted = await uploads.queueUploads([file],
              sourceKey: photo.key,
              wifiOnly: _preferences.wifiOnly,
              stillAllowed: () =>
                  _current(generation, owner) &&
                  _preferences.enabled &&
                  _foreground);
          if (accepted == 0) {
            _message = uploads.errorMessage ??
                'Backup paused. Review your upload queue.';
            return;
          }
          queued += accepted;
          if (queued >= 5) {
            wholePage = false;
            break;
          }
        }
        if (wholePage) _pages[album] = photos.length < 50 ? 0 : page + 1;
        if (queued >= 5) break;
      }
      _message = skipped > 0
          ? 'Some items need attention. Live Photos need a separate original-preserving backup path.'
          : queued > 0
              ? 'Added $queued ${queued == 1 ? 'memory' : 'memories'} to your upload queue.'
              : 'Checked your selected albums. Nothing new to add.';
    } catch (_) {
      if (_current(generation, owner)) {
        _message =
            'Backup paused. Check storage, access and connection, then try again.';
      }
    } finally {
      if (_current(generation, owner)) {
        _busy = false;
        _notify();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    _timer?.cancel();
    auth.removeListener(_authChanged);
    unawaited(library.stopObserving());
    super.dispose();
  }
}
