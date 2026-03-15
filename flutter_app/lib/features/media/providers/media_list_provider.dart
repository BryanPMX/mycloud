import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/api_transport.dart';
import '../../auth/providers/auth_provider.dart';
import '../domain/media.dart';

class MediaListProvider extends ChangeNotifier {
  MediaListProvider({
    required AppConfig config,
    required ApiClient apiClient,
    required ApiTransport transport,
    required AuthProvider authProvider,
  })  : _config = config,
        _apiClient = apiClient,
        _transport = transport,
        _authProvider = authProvider,
        _items = List<Media>.of(
          config.useDemoData ? _seedItems : const <Media>[],
        ) {
    if (_items.isNotEmpty) {
      _selectedMediaId = _items.first.id;
    }
  }

  final AppConfig _config;
  final ApiClient _apiClient;
  final ApiTransport _transport;
  final AuthProvider _authProvider;

  static final List<Media> _seedItems = <Media>[
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
      thumbUrls: ThumbUrls(
        small: 'media-1/small.webp',
        medium: 'media-1/medium.webp',
        large: 'media-1/large.webp',
      ),
    ),
    Media(
      id: 'media-2',
      ownerId: 'user-member',
      filename: 'lake-walk.mov',
      mimeType: 'video/quicktime',
      sizeBytes: 248034123,
      width: 1920,
      height: 1080,
      durationSecs: 48,
      status: MediaStatus.pending,
      isFavorite: false,
      takenAt: DateTime.utc(2025, 8, 18, 2, 10),
      uploadedAt: DateTime.utc(2025, 8, 18, 2, 18),
      thumbUrls: ThumbUrls(poster: 'media-2/poster.webp'),
    ),
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
      thumbUrls: ThumbUrls(
        small: 'media-3/small.webp',
        medium: 'media-3/medium.webp',
        large: 'media-3/large.webp',
      ),
    ),
    Media(
      id: 'media-4',
      ownerId: 'user-member',
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
      thumbUrls: ThumbUrls(
        small: 'media-4/small.webp',
        medium: 'media-4/medium.webp',
        large: 'media-4/large.webp',
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
      thumbUrls: ThumbUrls(
        medium: 'media-5/medium.webp',
        large: 'media-5/large.webp',
        poster: 'media-5/poster.webp',
      ),
    ),
  ];

  final List<Media> _items;
  final Map<String, String> _thumbnailUrls = <String, String>{};
  final Set<String> _thumbnailLoadsInFlight = <String>{};

  String _query = '';
  bool _favoritesOnly = false;
  String? _selectedMediaId;
  bool _isLoading = false;
  bool _hasLoaded = false;
  String? _errorMessage;
  Timer? _searchDebounce;
  int _requestSequence = 0;

  String get query => _query;

  bool get favoritesOnly => _favoritesOnly;

  bool get isLoading => _isLoading;

  bool get hasLoaded => _hasLoaded;

  String? get errorMessage => _errorMessage;

  List<Media> get allItems => List<Media>.unmodifiable(_items);

  List<Media> get visibleItems {
    final normalizedQuery =
        _config.useDemoData ? _query.trim().toLowerCase() : '';
    return _items.where((media) {
      final matchesQuery = normalizedQuery.isEmpty ||
          media.filename.toLowerCase().contains(normalizedQuery) ||
          media.mimeType.toLowerCase().contains(normalizedQuery);
      final matchesFavorite = !_favoritesOnly || media.isFavorite;
      return matchesQuery && matchesFavorite;
    }).toList(growable: false);
  }

  List<Media> get pendingItems => _items
      .where((media) => media.status == MediaStatus.pending)
      .toList(growable: false);

  Media? get selectedMedia {
    if (_selectedMediaId == null) {
      return null;
    }

    for (final media in visibleItems) {
      if (media.id == _selectedMediaId) {
        return media;
      }
    }

    for (final media in _items) {
      if (media.id == _selectedMediaId) {
        return media;
      }
    }

    return null;
  }

  int get readyCount =>
      _items.where((item) => item.status == MediaStatus.ready).length;

  String? thumbnailUrlFor(String mediaId) => _thumbnailUrls[mediaId];

  Future<void> load() async {
    if (_config.useDemoData) {
      _hasLoaded = true;
      notifyListeners();
      return;
    }

    final requestId = ++_requestSequence;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final uri = _query.trim().isEmpty
          ? _apiClient.endpoint(
              '/media',
              queryParameters: <String, String>{
                'limit': '50',
                if (_favoritesOnly) 'favorites': 'true',
              },
            )
          : _apiClient.endpoint(
              '/media/search',
              queryParameters: <String, String>{
                'q': _query.trim(),
                'limit': '50',
              },
            );

      final response = await _authProvider.withAuthorization(
        (headers) => _transport.get(uri, headers: headers),
      );
      if (requestId != _requestSequence) {
        return;
      }

      final payload = response.asMap();
      final rawItems = payload['items'] as List<dynamic>? ?? const <dynamic>[];
      final items = rawItems
          .whereType<Map<String, dynamic>>()
          .map(Media.fromJson)
          .where((media) => !_favoritesOnly || media.isFavorite)
          .toList(growable: false);

      _items
        ..clear()
        ..addAll(items);
      _thumbnailUrls.clear();
      _thumbnailLoadsInFlight.clear();
      _syncSelectedMedia();
      _hasLoaded = true;
    } on ApiException catch (error) {
      if (requestId != _requestSequence) {
        return;
      }
      _errorMessage = error.message;
    } catch (_) {
      if (requestId != _requestSequence) {
        return;
      }
      _errorMessage = 'Unable to load the media library.';
    } finally {
      if (requestId == _requestSequence) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  void updateQuery(String value) {
    _query = value;
    if (_config.useDemoData) {
      _syncSelectedMedia();
      notifyListeners();
      return;
    }

    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      unawaited(load());
    });
    notifyListeners();
  }

  void toggleFavoritesOnly() {
    _favoritesOnly = !_favoritesOnly;
    if (_config.useDemoData) {
      _syncSelectedMedia();
      notifyListeners();
      return;
    }

    unawaited(load());
  }

  Future<void> toggleFavorite(String mediaId) async {
    final index = _items.indexWhere((media) => media.id == mediaId);
    if (index == -1) {
      return;
    }

    final current = _items[index];
    final updated = current.copyWith(isFavorite: !current.isFavorite);
    _items[index] = updated;
    notifyListeners();

    if (_config.useDemoData) {
      return;
    }

    try {
      final uri = updated.isFavorite
          ? _apiClient.favoriteMediaUri(mediaId)
          : _apiClient.favoriteMediaUri(mediaId);
      await _authProvider.withAuthorization((headers) {
        if (updated.isFavorite) {
          return _transport.postJson(uri, headers: headers);
        }

        return _transport.delete(uri, headers: headers);
      });
      if (_favoritesOnly && !updated.isFavorite) {
        _items.removeAt(index);
        _syncSelectedMedia();
        notifyListeners();
      }
    } on ApiException catch (error) {
      _items[index] = current;
      _errorMessage = error.message;
      notifyListeners();
    } catch (_) {
      _items[index] = current;
      _errorMessage = 'Unable to update favorites right now.';
      notifyListeners();
    }
  }

  void selectMedia(String mediaId) {
    if (_selectedMediaId == mediaId) {
      return;
    }

    _selectedMediaId = mediaId;
    notifyListeners();
  }

  Future<void> ensureThumbnailLoaded(Media media) async {
    if (_config.useDemoData ||
        media.status != MediaStatus.ready ||
        _thumbnailUrls.containsKey(media.id) ||
        _thumbnailLoadsInFlight.contains(media.id)) {
      return;
    }

    _thumbnailLoadsInFlight.add(media.id);
    try {
      final response = await _authProvider.withAuthorization(
        (headers) => _transport.get(
          _apiClient.mediaThumbUri(
            media.id,
            size: media.isVideo ? 'poster' : 'medium',
          ),
          headers: headers,
        ),
      );
      final payload = response.asMap();
      final url = payload['url'] as String?;
      if (url != null && url.isNotEmpty) {
        _thumbnailUrls[media.id] = url;
        notifyListeners();
      }
    } catch (_) {
      // Keep the gradient fallback if thumb reads fail.
    } finally {
      _thumbnailLoadsInFlight.remove(media.id);
    }
  }

  void insertPendingUpload({
    required String mediaId,
    required String ownerId,
    required String filename,
    required String mimeType,
    required int sizeBytes,
  }) {
    final placeholder = Media(
      id: mediaId,
      ownerId: ownerId,
      filename: filename,
      mimeType: mimeType,
      sizeBytes: sizeBytes,
      width: 0,
      height: 0,
      durationSecs: 0,
      status: MediaStatus.pending,
      isFavorite: false,
      uploadedAt: DateTime.now().toUtc(),
      thumbUrls: const ThumbUrls(),
    );

    _upsertMedia(placeholder, insertAtTop: true);
    notifyListeners();
  }

  void updateProcessingStatus(
    String mediaId, {
    required MediaStatus status,
    String? smallThumbKey,
    String? mediumThumbKey,
    String? largeThumbKey,
    String? posterThumbKey,
  }) {
    final index = _items.indexWhere((media) => media.id == mediaId);
    if (index == -1) {
      return;
    }

    final current = _items[index];
    final updated = current.copyWith(
      status: status,
      thumbUrls: ThumbUrls(
        small: smallThumbKey ?? current.thumbUrls.small,
        medium: mediumThumbKey ?? current.thumbUrls.medium,
        large: largeThumbKey ?? current.thumbUrls.large,
        poster: posterThumbKey ?? current.thumbUrls.poster,
      ),
    );
    _items[index] = updated;

    if (status != MediaStatus.ready) {
      _thumbnailUrls.remove(mediaId);
    } else {
      unawaited(ensureThumbnailLoaded(updated));
    }

    _syncSelectedMedia();
    notifyListeners();
  }

  Future<void> refreshMediaItem(String mediaId) async {
    if (_config.useDemoData) {
      return;
    }

    try {
      final response = await _authProvider.withAuthorization(
        (headers) => _transport.get(
          _apiClient.mediaDetailUri(mediaId),
          headers: headers,
        ),
      );
      final media = Media.fromJson(response.asMap());
      if (_upsertMedia(media, insertAtTop: true) &&
          media.status == MediaStatus.ready) {
        unawaited(ensureThumbnailLoaded(media));
      }
      notifyListeners();
    } catch (_) {
      // Keep the optimistic placeholder if the detail refresh fails.
    }
  }

  void reset() {
    _searchDebounce?.cancel();
    _query = '';
    _favoritesOnly = false;
    _isLoading = false;
    _hasLoaded = _config.useDemoData;
    _errorMessage = null;
    _thumbnailUrls.clear();
    _thumbnailLoadsInFlight.clear();
    _requestSequence++;
    _items
      ..clear()
      ..addAll(_config.useDemoData ? _seedItems : const <Media>[]);
    _selectedMediaId = _items.isEmpty ? null : _items.first.id;
    notifyListeners();
  }

  bool _upsertMedia(Media media, {required bool insertAtTop}) {
    final index = _items.indexWhere((item) => item.id == media.id);
    if (index == -1) {
      if (!_shouldInsertMedia(media)) {
        return false;
      }

      if (insertAtTop) {
        _items.insert(0, media);
      } else {
        _items.add(media);
      }
    } else {
      _items[index] = media;
    }

    _syncSelectedMedia();
    return true;
  }

  bool _shouldInsertMedia(Media media) {
    if (_favoritesOnly && !media.isFavorite) {
      return false;
    }

    final normalizedQuery = _query.trim().toLowerCase();
    if (normalizedQuery.isEmpty) {
      return true;
    }

    return media.filename.toLowerCase().contains(normalizedQuery) ||
        media.mimeType.toLowerCase().contains(normalizedQuery);
  }

  void _syncSelectedMedia() {
    final current = visibleItems;
    if (current.isEmpty) {
      _selectedMediaId = null;
      return;
    }

    final hasSelection = current.any((media) => media.id == _selectedMediaId);
    if (!hasSelection) {
      _selectedMediaId = current.first.id;
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }
}
