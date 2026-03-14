import 'package:flutter/foundation.dart';

import '../domain/album.dart';

class AlbumProvider extends ChangeNotifier {
  AlbumProvider()
      : _albums = [
          Album(
            id: 'album-1',
            ownerId: 'user-member',
            name: 'Weekend in Estes Park',
            description:
                'Cabin mornings, frozen lake walks, and the diner stop.',
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
            description:
                'Porch dinners, garden light, and the long golden evenings.',
            coverMediaId: 'media-1',
            mediaCount: 19,
            createdAt: DateTime.utc(2025, 8, 10),
            updatedAt: DateTime.utc(2025, 8, 18),
            isOwnedByCurrentUser: true,
          ),
          Album(
            id: 'album-3',
            ownerId: 'user-admin',
            name: 'Shared Family Highlights',
            description:
                'Cross-household favorites shared with the whole family.',
            coverMediaId: 'media-4',
            mediaCount: 88,
            createdAt: DateTime.utc(2026, 2, 1),
            updatedAt: DateTime.utc(2026, 3, 10),
            isOwnedByCurrentUser: false,
          ),
        ];

  final List<Album> _albums;

  List<Album> get ownedAlbums => _albums
      .where((album) => album.isOwnedByCurrentUser)
      .toList(growable: false);

  List<Album> get sharedAlbums => _albums
      .where((album) => !album.isOwnedByCurrentUser)
      .toList(growable: false);
}
