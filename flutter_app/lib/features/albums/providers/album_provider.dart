import 'package:flutter/foundation.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/api_transport.dart';
import '../../auth/providers/auth_provider.dart';
import '../domain/album.dart';

class AlbumProvider extends ChangeNotifier {
  AlbumProvider({
    required AppConfig config,
    required ApiClient apiClient,
    required ApiTransport transport,
    required AuthProvider authProvider,
  })  : _config = config,
        _apiClient = apiClient,
        _transport = transport,
        _authProvider = authProvider,
        _ownedAlbums = List<Album>.of(
          config.useDemoData ? _seedOwnedAlbums : const <Album>[],
        ),
        _sharedAlbums = List<Album>.of(
          config.useDemoData ? _seedSharedAlbums : const <Album>[],
        );

  final AppConfig _config;
  final ApiClient _apiClient;
  final ApiTransport _transport;
  final AuthProvider _authProvider;

  static final List<Album> _seedOwnedAlbums = <Album>[
    Album(
      id: 'album-1',
      ownerId: 'user-member',
      name: 'Weekend in Estes Park',
      description: 'Cabin mornings, frozen lake walks, and the diner stop.',
      coverMediaId: 'media-3',
      mediaCount: 42,
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
      mediaCount: 19,
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
      mediaCount: 88,
      createdAt: DateTime.utc(2026, 2, 1),
      updatedAt: DateTime.utc(2026, 3, 10),
      isOwnedByCurrentUser: false,
    ),
  ];

  final List<Album> _ownedAlbums;
  final List<Album> _sharedAlbums;

  bool _isLoading = false;
  bool _hasLoaded = false;
  bool _isCreating = false;
  String? _errorMessage;
  final Set<String> _savingAlbumIds = <String>{};
  final Set<String> _deletingAlbumIds = <String>{};

  bool get isLoading => _isLoading;

  bool get hasLoaded => _hasLoaded;

  bool get isCreating => _isCreating;

  String? get errorMessage => _errorMessage;

  List<Album> get ownedAlbums => List<Album>.unmodifiable(_ownedAlbums);

  List<Album> get sharedAlbums => List<Album>.unmodifiable(_sharedAlbums);

  bool isSavingAlbum(String albumId) => _savingAlbumIds.contains(albumId);

  bool isDeletingAlbum(String albumId) => _deletingAlbumIds.contains(albumId);

  Future<void> load() async {
    if (_config.useDemoData) {
      _hasLoaded = true;
      notifyListeners();
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

  Future<bool> createAlbum({
    required String name,
    required String description,
  }) async {
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
      _sortOwnedAlbums();
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
      _sortOwnedAlbums();
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

  void reset() {
    _isLoading = false;
    _hasLoaded = _config.useDemoData;
    _isCreating = false;
    _errorMessage = null;
    _savingAlbumIds.clear();
    _deletingAlbumIds.clear();
    _ownedAlbums
      ..clear()
      ..addAll(_config.useDemoData ? _seedOwnedAlbums : const <Album>[]);
    _sharedAlbums
      ..clear()
      ..addAll(_config.useDemoData ? _seedSharedAlbums : const <Album>[]);
    notifyListeners();
  }

  void _sortOwnedAlbums() {
    _ownedAlbums
        .sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
  }
}
