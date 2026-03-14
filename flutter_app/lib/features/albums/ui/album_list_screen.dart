import 'package:flutter/material.dart';

import '../../../shared/utils/date_formatter.dart';
import '../domain/album.dart';
import '../providers/album_provider.dart';

class AlbumListScreen extends StatelessWidget {
  const AlbumListScreen({super.key, required this.albumProvider});

  final AlbumProvider albumProvider;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ownedAlbums = albumProvider.ownedAlbums;
    final sharedAlbums = albumProvider.sharedAlbums;

    return SingleChildScrollView(
      key: const ValueKey<String>('album-list-screen'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Albums ready for the next API slice',
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'These cards mirror the owned/shared album split already exposed by GET /albums. The next step is wiring list, detail, and album-media reads to the backend.',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text('Owned by you', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 12),
          ...ownedAlbums.map((album) => _AlbumCard(album: album)),
          const SizedBox(height: 20),
          Text('Shared with you', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 12),
          ...sharedAlbums.map((album) => _AlbumCard(album: album)),
        ],
      ),
    );
  }
}

class _AlbumCard extends StatelessWidget {
  const _AlbumCard({required this.album});

  final Album album;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  Text(album.name, style: theme.textTheme.titleLarge),
                  Chip(
                    label: Text(
                      album.isOwnedByCurrentUser ? 'owned' : 'shared',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                album.description,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 14,
                runSpacing: 8,
                children: [
                  _AlbumMeta(label: '${album.mediaCount} items'),
                  _AlbumMeta(
                    label:
                        'Updated ${DateFormatter.mediumDate(album.updatedAt)}',
                  ),
                  if (album.coverMediaId != null)
                    _AlbumMeta(label: 'Cover ${album.coverMediaId}'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AlbumMeta extends StatelessWidget {
  const _AlbumMeta({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label),
    );
  }
}
