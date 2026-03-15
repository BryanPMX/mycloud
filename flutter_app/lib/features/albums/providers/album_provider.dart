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
  String? _errorMessage;

  bool get isLoading => _isLoading;

  bool get hasLoaded => _hasLoaded;

  String? get errorMessage => _errorMessage;

  List<Album> get ownedAlbums => List<Album>.unmodifiable(_ownedAlbums);

  List<Album> get sharedAlbums => List<Album>.unmodifiable(_sharedAlbums);

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

  void reset() {
    _isLoading = false;
    _hasLoaded = _config.useDemoData;
    _errorMessage = null;
    _ownedAlbums
      ..clear()
      ..addAll(_config.useDemoData ? _seedOwnedAlbums : const <Album>[]);
    _sharedAlbums
      ..clear()
      ..addAll(_config.useDemoData ? _seedSharedAlbums : const <Album>[]);
    notifyListeners();
  }
}
