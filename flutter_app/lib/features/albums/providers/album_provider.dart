import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../../core/config/app_config.dart';
import '../../../core/connectivity/connectivity_service.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/api_transport.dart';
import '../../auth/providers/auth_provider.dart';
import '../../media/domain/media.dart';
import '../domain/album.dart';
import '../domain/album_share.dart';

class AlbumProvider extends ChangeNotifier {
  AlbumProvider({
    required AppConfig config,
    required ApiClient apiClient,
    required ApiTransport transport,
    required AuthProvider authProvider,
    required ConnectivityService connectivityService,
  })  : _config = config,
        _apiClient = apiClient,
        _transport = transport,
        _authProvider = authProvider,
        _connectivityService = connectivityService,
        _ownedAlbums = List<Album>.of(
          config.useDemoData ? _seedOwnedAlbums : const <Album>[],
        ),
        _sharedAlbums = List<Album>.of(
          config.useDemoData ? _seedSharedAlbums : const <Album>[],
        ) {
    if (_config.useDemoData) {
      for (final entry in _seedAlbumMedia.entries) {
        _albumMedia[entry.key] = List<Media>.of(entry.value);
        _loadedAlbumMediaIds.add(entry.key);
      }
      for (final entry in _seedAlbumShares.entries) {
        _albumShares[entry.key] = List<AlbumShare>.of(entry.value);
        _loadedShareAlbumIds.add(entry.key);
      }
    }
  }

  static final List<Album> _seedOwnedAlbums = <Album>[
    Album(
      id: 'album-1',
      ownerId: 'user-member',
      name: 'Weekend in Estes Park',
      description: 'Cabin mornings, frozen lake walks, and the diner stop.',
      coverMediaId: 'media-3',
      mediaCount: 2,
      createdAt: DateTime.utc(2025, 12, 20),
      updatedAt: DateTime.utc(2026, 1, 3),
      isOwnedByCurrentUser: true,
    ),
    Album(
      id: 'album-2',
      ownerId: 'user-member',
      name: 'Backyard Summer',
      description: 'Porch dinners, garden light, and the long golden evenings.',
      coverMediaId: 'media-1',
      mediaCount: 1,
      createdAt: DateTime.utc(2025, 8, 10),
      updatedAt: DateTime.utc(2025, 8, 18),
      isOwnedByCurrentUser: true,
    ),
  ];

  static final List<Album> _seedSharedAlbums = <Album>[
    Album(
      id: 'album-3',
      ownerId: 'user-admin',
      name: 'Shared Family Highlights',
      description: 'Cross-household favorites shared with the whole family.',
      coverMediaId: 'media-4',
      mediaCount: 2,
      createdAt: DateTime.utc(2026, 2, 1),
      updatedAt: DateTime.utc(2026, 3, 10),
      isOwnedByCurrentUser: false,
    ),
  ];

  static final Map<String, List<Media>> _seedAlbumMedia = <String, List<Media>>{
    'album-1': <Media>[
      Media(
        id: 'media-3',
        ownerId: 'user-member',
        filename: 'winter-cabin.heic',
        mimeType: 'image/heic',
        sizeBytes: 9123401,
        width: 3024,
        height: 4032,
        durationSecs: 0,
        status: MediaStatus.ready,
        isFavorite: false,
        takenAt: DateTime.utc(2025, 12, 22, 17, 40),
        uploadedAt: DateTime.utc(2025, 12, 22, 18, 2),
        thumbUrls: const ThumbUrls(
          small: 'media-3/small.webp',
          medium: 'media-3/medium.webp',
          large: 'media-3/large.webp',
        ),
      ),
      Media(
        id: 'media-5',
        ownerId: 'user-member',
        filename: 'first-bike-ride.mp4',
        mimeType: 'video/mp4',
        sizeBytes: 389120445,
        width: 3840,
        height: 2160,
        durationSecs: 76,
        status: MediaStatus.ready,
        isFavorite: false,
        takenAt: DateTime.utc(2026, 2, 2, 20, 5),
        uploadedAt: DateTime.utc(2026, 2, 2, 20, 19),
        thumbUrls: const ThumbUrls(
          medium: 'media-5/medium.webp',
          large: 'media-5/large.webp',
          poster: 'media-5/poster.webp',
        ),
      ),
    ],
    'album-2': <Media>[
      Media(
        id: 'media-1',
        ownerId: 'user-member',
        filename: 'golden-hour-porch.jpg',
        mimeType: 'image/jpeg',
        sizeBytes: 6843210,
        width: 4032,
        height: 3024,
        durationSecs: 0,
        status: MediaStatus.ready,
        isFavorite: true,
        takenAt: DateTime.utc(2025, 8, 18, 1, 14),
        uploadedAt: DateTime.utc(2025, 8, 18, 1, 18),
        thumbUrls: const ThumbUrls(
          small: 'media-1/small.webp',
          medium: 'media-1/medium.webp',
          large: 'media-1/large.webp',
        ),
      ),
    ],
    'album-3': <Media>[
      Media(
        id: 'media-4',
        ownerId: 'user-admin',
        filename: 'garden-brunch.png',
        mimeType: 'image/png',
        sizeBytes: 5132201,
        width: 2048,
        height: 1365,
        durationSecs: 0,
        status: MediaStatus.ready,
        isFavorite: true,
        takenAt: DateTime.utc(2026, 3, 6, 16, 20),
        uploadedAt: DateTime.utc(2026, 3, 6, 16, 32),
        thumbUrls: const ThumbUrls(
          small: 'media-4/small.webp',
          medium: 'media-4/medium.webp',
          large: 'media-4/large.webp',
        ),
      ),
      Media(
        id: 'media-6',
        ownerId: 'user-admin',
        filename: 'family-toast.jpg',
        mimeType: 'image/jpeg',
        sizeBytes: 4048123,
        width: 3024,
        height: 2016,
        durationSecs: 0,
        status: MediaStatus.ready,
        isFavorite: false,
        takenAt: DateTime.utc(2026, 3, 7, 18, 22),
        uploadedAt: DateTime.utc(2026, 3, 7, 18, 25),
        thumbUrls: const ThumbUrls(
          small: 'media-6/small.webp',
          medium: 'media-6/medium.webp',
          large: 'media-6/large.webp',
        ),
      ),
    ],
  };

  static final Map<String, List<AlbumShare>> _seedAlbumShares =
      <String, List<AlbumShare>>{
    'album-3': <AlbumShare>[
      AlbumShare(
        id: 'share-1',
        albumId: 'album-3',
        sharedBy: 'user-admin',
        sharedWith: AlbumShare.familyRecipientId,
        recipient: const AlbumShareRecipient(
          id: AlbumShare.familyRecipientId,
          displayName: 'Entire family',
        ),
        permission: AlbumPermission.view,
        createdAt: DateTime.utc(2026, 3, 8, 12),
      ),
    ],
  };

  final AppConfig _config;
  final ApiClient _apiClient;
  final ApiTransport _transport;
  final AuthProvider _authProvider;
  final ConnectivityService _connectivityService;

  final List<Album> _ownedAlbums;
  final List<Album> _sharedAlbums;
  final Map<String, List<Media>> _albumMedia = <String, List<Media>>{};
  final Map<String, List<AlbumShare>> _albumShares =
      <String, List<AlbumShare>>{};
  final Set<String> _loadingAlbumMediaIds = <String>{};
  final Set<String> _loadedAlbumMediaIds = <String>{};
  final Set<String> _loadingShareAlbumIds = <String>{};
  final Set<String> _loadedShareAlbumIds = <String>{};
  final Set<String> _savingAlbumIds = <String>{};
  final Set<String> _deletingAlbumIds = <String>{};
  final Set<String> _mutatingAlbumMediaIds = <String>{};
  final Set<String> _mutatingAlbumShareIds = <String>{};

  bool _isLoading = false;
  bool _hasLoaded = false;
  bool _isCreating = false;
  String? _errorMessage;

  bool get isLoading => _isLoading;

  bool get hasLoaded => _hasLoaded;

  bool get isCreating => _isCreating;

  String? get errorMessage => _errorMessage;

  List<Album> get ownedAlbums => List<Album>.unmodifiable(_ownedAlbums);

  List<Album> get sharedAlbums => List<Album>.unmodifiable(_sharedAlbums);

  bool isSavingAlbum(String albumId) => _savingAlbumIds.contains(albumId);

  bool isDeletingAlbum(String albumId) => _deletingAlbumIds.contains(albumId);

  bool isLoadingAlbumMedia(String albumId) =>
      _loadingAlbumMediaIds.contains(albumId);

  bool hasLoadedAlbumMedia(String albumId) =>
      _loadedAlbumMediaIds.contains(albumId);

  bool isMutatingAlbumMedia(String albumId) =>
      _mutatingAlbumMediaIds.contains(albumId);

  bool isLoadingAlbumShares(String albumId) =>
      _loadingShareAlbumIds.contains(albumId);

  bool hasLoadedAlbumShares(String albumId) =>
      _loadedShareAlbumIds.contains(albumId);

  bool isMutatingAlbumShares(String albumId) =>
      _mutatingAlbumShareIds.contains(albumId);

  bool canManage(Album album) =>
      album.isOwnedByCurrentUser || _authProvider.canAccessAdmin;

  List<Media> mediaForAlbum(String albumId) =>
      List<Media>.unmodifiable(_albumMedia[albumId] ?? const <Media>[]);

  List<AlbumShare> sharesForAlbum(String albumId) =>
      List<AlbumShare>.unmodifiable(
          _albumShares[albumId] ?? const <AlbumShare>[]);

  Future<void> load() async {
    if (_config.useDemoData) {
      _hasLoaded = true;
      notifyListeners();
      return;
    }
    if (_blockIfOffline()) {
      return;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final response = await _authProvider.withAuthorization(
        (headers) => _transport.get(_apiClient.albumsUri(), headers: headers),
      );
      final payload = response.asMap();
      final owned = payload['owned'] as List<dynamic>? ?? const <dynamic>[];
      final shared =
          payload['shared_with_me'] as List<dynamic>? ?? const <dynamic>[];

      _ownedAlbums
        ..clear()
        ..addAll(
          owned
              .whereType<Map<String, dynamic>>()
              .map((json) => Album.fromJson(json, isOwnedByCurrentUser: true)),
        );
      _sharedAlbums
        ..clear()
        ..addAll(
          shared
              .whereType<Map<String, dynamic>>()
              .map((json) => Album.fromJson(json, isOwnedByCurrentUser: false)),
        );
      _sortAlbums();
      _hasLoaded = true;
    } on ApiException catch (error) {
      _errorMessage = error.message;
    } catch (_) {
      _errorMessage = 'Unable to load albums right now.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadAlbumMedia(String albumId) async {
    if (_config.useDemoData) {
      _loadedAlbumMediaIds.add(albumId);
      notifyListeners();
      return;
    }
    if (_blockIfOffline()) {
      return;
    }

    _loadingAlbumMediaIds.add(albumId);
    _errorMessage = null;
    notifyListeners();

    try {
      final response = await _authProvider.withAuthorization(
        (headers) => _transport.get(
          _apiClient.endpoint(
            '/albums/$albumId/media',
            queryParameters: const <String, String>{'limit': '50'},
          ),
          headers: headers,
        ),
      );
      final payload = response.asMap();
      final items = (payload['items'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(Media.fromJson)
          .toList(growable: false);
      _albumMedia[albumId] = items;
      _loadedAlbumMediaIds.add(albumId);
    } on ApiException catch (error) {
      _errorMessage = error.message;
    } catch (_) {
      _errorMessage = 'Unable to load album items right now.';
    } finally {
      _loadingAlbumMediaIds.remove(albumId);
      notifyListeners();
    }
  }

  Future<void> loadAlbumShares(String albumId) async {
    if (_config.useDemoData) {
      _loadedShareAlbumIds.add(albumId);
      notifyListeners();
      return;
    }
    if (_blockIfOffline()) {
      return;
    }

    _loadingShareAlbumIds.add(albumId);
    _errorMessage = null;
    notifyListeners();

    try {
      final response = await _authProvider.withAuthorization(
        (headers) => _transport.get(_apiClient.albumSharesUri(albumId),
            headers: headers),
      );
      final payload = response.asMap();
      final shares = (payload['shares'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(AlbumShare.fromJson)
          .toList(growable: false);
      _albumShares[albumId] = shares;
      _loadedShareAlbumIds.add(albumId);
    } on ApiException catch (error) {
      _errorMessage = error.message;
    } catch (_) {
      _errorMessage = 'Unable to load album shares right now.';
    } finally {
      _loadingShareAlbumIds.remove(albumId);
      notifyListeners();
    }
  }

  Future<bool> createAlbum({
    required String name,
    required String description,
  }) async {
    if (!_config.useDemoData && _blockIfOffline()) {
      return false;
    }

    final trimmedName = name.trim();
    final trimmedDescription = description.trim();
    if (trimmedName.isEmpty) {
      _errorMessage = 'Album name cannot be empty.';
      notifyListeners();
      return false;
    }

    _isCreating = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final album = _config.useDemoData
          ? Album(
              id: 'demo-album-${DateTime.now().microsecondsSinceEpoch}',
              ownerId: _authProvider.currentUser?.id ?? 'demo-user',
              name: trimmedName,
              description: trimmedDescription,
              mediaCount: 0,
              createdAt: DateTime.now().toUtc(),
              updatedAt: DateTime.now().toUtc(),
              isOwnedByCurrentUser: true,
            )
          : Album.fromJson(
              (await _authProvider.withAuthorization(
                (headers) => _transport.postJson(
                  _apiClient.albumsUri(),
                  headers: headers,
                  body: <String, String>{
                    'name': trimmedName,
                    'description': trimmedDescription,
                  },
                ),
              ))
                  .asMap(),
              isOwnedByCurrentUser: true,
            );

      _ownedAlbums.insert(0, album);
      _sortAlbums();
      _hasLoaded = true;
      notifyListeners();
      return true;
    } on ApiException catch (error) {
      _errorMessage = error.message;
      notifyListeners();
      return false;
    } catch (_) {
      _errorMessage = 'Unable to create the album right now.';
      notifyListeners();
      return false;
    } finally {
      _isCreating = false;
      notifyListeners();
    }
  }

  Future<bool> updateAlbum({
    required String albumId,
    required String name,
    required String description,
  }) async {
    if (!_config.useDemoData && _blockIfOffline()) {
      return false;
    }

    final index = _ownedAlbums.indexWhere((album) => album.id == albumId);
    final trimmedName = name.trim();
    final trimmedDescription = description.trim();
    if (index == -1) {
      return false;
    }
    if (trimmedName.isEmpty) {
      _errorMessage = 'Album name cannot be empty.';
      notifyListeners();
      return false;
    }

    _savingAlbumIds.add(albumId);
    _errorMessage = null;
    notifyListeners();

    try {
      final updatedAlbum = _config.useDemoData
          ? _ownedAlbums[index].copyWith(
              name: trimmedName,
              description: trimmedDescription,
              updatedAt: DateTime.now().toUtc(),
            )
          : Album.fromJson(
              (await _authProvider.withAuthorization(
                (headers) => _transport.patchJson(
                  _apiClient.albumDetailUri(albumId),
                  headers: headers,
                  body: <String, String>{
                    'name': trimmedName,
                    'description': trimmedDescription,
                  },
                ),
              ))
                  .asMap(),
              isOwnedByCurrentUser: true,
            );

      _ownedAlbums[index] = updatedAlbum;
      _sortAlbums();
      notifyListeners();
      return true;
    } on ApiException catch (error) {
      _errorMessage = error.message;
      notifyListeners();
      return false;
    } catch (_) {
      _errorMessage = 'Unable to update the album right now.';
      notifyListeners();
      return false;
    } finally {
      _savingAlbumIds.remove(albumId);
      notifyListeners();
    }
  }

  Future<bool> deleteAlbum(String albumId) async {
    if (!_config.useDemoData && _blockIfOffline()) {
      return false;
    }

    final index = _ownedAlbums.indexWhere((album) => album.id == albumId);
    if (index == -1) {
      return false;
    }

    _deletingAlbumIds.add(albumId);
    _errorMessage = null;
    notifyListeners();

    try {
      if (!_config.useDemoData) {
        await _authProvider.withAuthorization(
          (headers) => _transport.delete(
            _apiClient.albumDetailUri(albumId),
            headers: headers,
          ),
        );
      }

      _ownedAlbums.removeAt(index);
      _albumMedia.remove(albumId);
      _albumShares.remove(albumId);
      _loadedAlbumMediaIds.remove(albumId);
      _loadedShareAlbumIds.remove(albumId);
      notifyListeners();
      return true;
    } on ApiException catch (error) {
      _errorMessage = error.message;
      notifyListeners();
      return false;
    } catch (_) {
      _errorMessage = 'Unable to delete the album right now.';
      notifyListeners();
      return false;
    } finally {
      _deletingAlbumIds.remove(albumId);
      notifyListeners();
    }
  }

  Future<bool> addMediaToAlbum({
    required String albumId,
    required List<Media> media,
  }) async {
    if (!_config.useDemoData && _blockIfOffline()) {
      return false;
    }

    if (media.isEmpty) {
      _errorMessage = 'Choose at least one media item to add.';
      notifyListeners();
      return false;
    }

    _mutatingAlbumMediaIds.add(albumId);
    _errorMessage = null;
    notifyListeners();

    try {
      var addedCount = 0;
      if (_config.useDemoData) {
        final existing =
            List<Media>.of(_albumMedia[albumId] ?? const <Media>[]);
        final existingIds = existing.map((item) => item.id).toSet();
        for (final item in media) {
          if (existingIds.add(item.id)) {
            existing.add(item);
            addedCount++;
          }
        }
        existing.sort(
          (left, right) => right.uploadedAt.compareTo(left.uploadedAt),
        );
        _albumMedia[albumId] = existing;
        _loadedAlbumMediaIds.add(albumId);
      } else {
        final response = await _authProvider.withAuthorization(
          (headers) => _transport.postJson(
            _apiClient.albumMediaUri(albumId),
            headers: headers,
            body: <String, Object>{
              'media_ids': media.map((item) => item.id).toList(growable: false),
            },
          ),
        );
        addedCount = _asInt(response.asMap()['added']);
        await loadAlbumMedia(albumId);
      }

      if (addedCount > 0) {
        _updateAlbum(
          albumId,
          (album) => album.copyWith(
            mediaCount: album.mediaCount + addedCount,
            updatedAt: DateTime.now().toUtc(),
            coverMediaId: album.coverMediaId ?? media.first.id,
          ),
        );
      }
      notifyListeners();
      return true;
    } on ApiException catch (error) {
      _errorMessage = error.message;
      notifyListeners();
      return false;
    } catch (_) {
      _errorMessage = 'Unable to add media to the album right now.';
      notifyListeners();
      return false;
    } finally {
      _mutatingAlbumMediaIds.remove(albumId);
      notifyListeners();
    }
  }

  Future<bool> removeMediaFromAlbum({
    required String albumId,
    required String mediaId,
  }) async {
    if (!_config.useDemoData && _blockIfOffline()) {
      return false;
    }

    _mutatingAlbumMediaIds.add(albumId);
    _errorMessage = null;
    notifyListeners();

    try {
      if (_config.useDemoData) {
        final existing =
            List<Media>.of(_albumMedia[albumId] ?? const <Media>[]);
        existing.removeWhere((item) => item.id == mediaId);
        _albumMedia[albumId] = existing;
        _loadedAlbumMediaIds.add(albumId);
      } else {
        await _authProvider.withAuthorization(
          (headers) => _transport.delete(
            _apiClient.albumMediaItemUri(albumId, mediaId),
            headers: headers,
          ),
        );
        final existing =
            List<Media>.of(_albumMedia[albumId] ?? const <Media>[]);
        existing.removeWhere((item) => item.id == mediaId);
        _albumMedia[albumId] = existing;
      }

      _updateAlbum(
        albumId,
        (album) => album.copyWith(
          mediaCount: math.max(0, album.mediaCount - 1),
          updatedAt: DateTime.now().toUtc(),
          coverMediaId:
              album.coverMediaId == mediaId ? null : album.coverMediaId,
        ),
      );
      notifyListeners();
      return true;
    } on ApiException catch (error) {
      _errorMessage = error.message;
      notifyListeners();
      return false;
    } catch (_) {
      _errorMessage = 'Unable to remove the item from the album right now.';
      notifyListeners();
      return false;
    } finally {
      _mutatingAlbumMediaIds.remove(albumId);
      notifyListeners();
    }
  }

  Future<bool> createShare({
    required String albumId,
    required AlbumPermission permission,
    String? sharedWith,
    DateTime? expiresAt,
  }) async {
    if (!_config.useDemoData && _blockIfOffline()) {
      return false;
    }

    _mutatingAlbumShareIds.add(albumId);
    _errorMessage = null;
    notifyListeners();

    try {
      final share = _config.useDemoData
          ? AlbumShare(
              id: 'share-${DateTime.now().microsecondsSinceEpoch}',
              albumId: albumId,
              sharedBy: _authProvider.currentUser?.id ?? 'user-member',
              sharedWith: sharedWith ?? AlbumShare.familyRecipientId,
              recipient: sharedWith == null
                  ? const AlbumShareRecipient(
                      id: AlbumShare.familyRecipientId,
                      displayName: 'Entire family',
                    )
                  : AlbumShareRecipient(
                      id: sharedWith,
                      displayName: sharedWith == 'user-admin'
                          ? 'Admin Operator'
                          : 'Family Member',
                    ),
              permission: permission,
              expiresAt: expiresAt,
              createdAt: DateTime.now().toUtc(),
            )
          : AlbumShare.fromJson(
              (await _authProvider.withAuthorization(
                (headers) => _transport.postJson(
                  _apiClient.albumSharesUri(albumId),
                  headers: headers,
                  body: <String, Object>{
                    if (sharedWith != null && sharedWith.trim().isNotEmpty)
                      'shared_with': sharedWith,
                    'permission': permission.apiValue,
                    if (expiresAt != null)
                      'expires_at': expiresAt.toUtc().toIso8601String(),
                  },
                ),
              ))
                  .asMap(),
            );

      final shares =
          List<AlbumShare>.of(_albumShares[albumId] ?? const <AlbumShare>[])
            ..insert(0, share);
      _albumShares[albumId] = shares;
      _loadedShareAlbumIds.add(albumId);
      notifyListeners();
      return true;
    } on ApiException catch (error) {
      _errorMessage = error.message;
      notifyListeners();
      return false;
    } catch (_) {
      _errorMessage = 'Unable to share the album right now.';
      notifyListeners();
      return false;
    } finally {
      _mutatingAlbumShareIds.remove(albumId);
      notifyListeners();
    }
  }

  Future<bool> revokeShare({
    required String albumId,
    required String shareId,
  }) async {
    if (!_config.useDemoData && _blockIfOffline()) {
      return false;
    }

    _mutatingAlbumShareIds.add(albumId);
    _errorMessage = null;
    notifyListeners();

    try {
      if (!_config.useDemoData) {
        await _authProvider.withAuthorization(
          (headers) => _transport.delete(
            _apiClient.albumShareUri(albumId, shareId),
            headers: headers,
          ),
        );
      }

      final shares =
          List<AlbumShare>.of(_albumShares[albumId] ?? const <AlbumShare>[])
            ..removeWhere((share) => share.id == shareId);
      _albumShares[albumId] = shares;
      notifyListeners();
      return true;
    } on ApiException catch (error) {
      _errorMessage = error.message;
      notifyListeners();
      return false;
    } catch (_) {
      _errorMessage = 'Unable to revoke the share right now.';
      notifyListeners();
      return false;
    } finally {
      _mutatingAlbumShareIds.remove(albumId);
      notifyListeners();
    }
  }

  void reset() {
    _isLoading = false;
    _hasLoaded = _config.useDemoData;
    _isCreating = false;
    _errorMessage = null;
    _savingAlbumIds.clear();
    _deletingAlbumIds.clear();
    _loadingAlbumMediaIds.clear();
    _loadedAlbumMediaIds.clear();
    _loadingShareAlbumIds.clear();
    _loadedShareAlbumIds.clear();
    _mutatingAlbumMediaIds.clear();
    _mutatingAlbumShareIds.clear();
    _ownedAlbums
      ..clear()
      ..addAll(_config.useDemoData ? _seedOwnedAlbums : const <Album>[]);
    _sharedAlbums
      ..clear()
      ..addAll(_config.useDemoData ? _seedSharedAlbums : const <Album>[]);
    _albumMedia.clear();
    _albumShares.clear();
    if (_config.useDemoData) {
      for (final entry in _seedAlbumMedia.entries) {
        _albumMedia[entry.key] = List<Media>.of(entry.value);
        _loadedAlbumMediaIds.add(entry.key);
      }
      for (final entry in _seedAlbumShares.entries) {
        _albumShares[entry.key] = List<AlbumShare>.of(entry.value);
        _loadedShareAlbumIds.add(entry.key);
      }
    }
    notifyListeners();
  }

  void _sortAlbums() {
    _ownedAlbums
        .sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
    _sharedAlbums
        .sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
  }

  void _updateAlbum(String albumId, Album Function(Album album) transform) {
    final ownedIndex = _ownedAlbums.indexWhere((album) => album.id == albumId);
    if (ownedIndex != -1) {
      _ownedAlbums[ownedIndex] = transform(_ownedAlbums[ownedIndex]);
      _sortAlbums();
      return;
    }

    final sharedIndex =
        _sharedAlbums.indexWhere((album) => album.id == albumId);
    if (sharedIndex != -1) {
      _sharedAlbums[sharedIndex] = transform(_sharedAlbums[sharedIndex]);
      _sortAlbums();
    }
  }

  int _asInt(Object? value) {
    if (value is num) {
      return value.toInt();
    }

    return 0;
  }

  bool _blockIfOffline() {
    if (_connectivityService.isOffline) {
      _errorMessage = _connectivityService.statusMessage;
      notifyListeners();
      return true;
    }

    return false;
  }
}
