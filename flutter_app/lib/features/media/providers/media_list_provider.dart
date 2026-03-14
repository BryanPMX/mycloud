import 'package:flutter/foundation.dart';

import '../domain/media.dart';

class MediaListProvider extends ChangeNotifier {
  MediaListProvider()
      : _items = [
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
            thumbUrls: const ThumbUrls(poster: 'media-2/poster.webp'),
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
            thumbUrls: const ThumbUrls(
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
            thumbUrls: const ThumbUrls(
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
            thumbUrls: const ThumbUrls(
              medium: 'media-5/medium.webp',
              large: 'media-5/large.webp',
              poster: 'media-5/poster.webp',
            ),
          ),
        ] {
    _selectedMediaId = _items.first.id;
  }

  final List<Media> _items;

  String _query = '';
  bool _favoritesOnly = false;
  String? _selectedMediaId;

  String get query => _query;

  bool get favoritesOnly => _favoritesOnly;

  List<Media> get visibleItems {
    final normalizedQuery = _query.trim().toLowerCase();
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

    for (final media in _items) {
      if (media.id == _selectedMediaId) {
        return media;
      }
    }

    return null;
  }

  int get readyCount =>
      _items.where((item) => item.status == MediaStatus.ready).length;

  void updateQuery(String value) {
    _query = value;
    notifyListeners();
  }

  void toggleFavoritesOnly() {
    _favoritesOnly = !_favoritesOnly;
    notifyListeners();
  }

  void toggleFavorite(String mediaId) {
    final index = _items.indexWhere((media) => media.id == mediaId);
    if (index == -1) {
      return;
    }

    _items[index] = _items[index].copyWith(
      isFavorite: !_items[index].isFavorite,
    );
    notifyListeners();
  }

  void selectMedia(String mediaId) {
    _selectedMediaId = mediaId;
    notifyListeners();
  }
}
