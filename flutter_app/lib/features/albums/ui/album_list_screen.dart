import 'package:flutter/material.dart';

import '../../../shared/utils/date_formatter.dart';
import '../domain/album.dart';
import '../providers/album_provider.dart';

class AlbumListScreen extends StatelessWidget {
  const AlbumListScreen({super.key, required this.albumProvider});

  final AlbumProvider albumProvider;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: albumProvider,
      builder: (context, _) {
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
                        'Live album lists',
                        style: theme.textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Owned and shared album collections now come from GET /albums so this section reflects the real backend state instead of seeded placeholders.',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (albumProvider.errorMessage != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          albumProvider.errorMessage!,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              if (albumProvider.isLoading && !albumProvider.hasLoaded)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(),
                  ),
                )
              else ...[
                Text('Owned by you', style: theme.textTheme.headlineSmall),
                const SizedBox(height: 12),
                if (ownedAlbums.isEmpty)
                  const _AlbumEmptyState(message: 'No owned albums yet.')
                else
                  ...ownedAlbums.map((album) => _AlbumCard(album: album)),
                const SizedBox(height: 20),
                Text('Shared with you', style: theme.textTheme.headlineSmall),
                const SizedBox(height: 12),
                if (sharedAlbums.isEmpty)
                  const _AlbumEmptyState(message: 'No shared albums yet.')
                else
                  ...sharedAlbums.map((album) => _AlbumCard(album: album)),
              ],
            ],
          ),
        );
      },
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

class _AlbumEmptyState extends StatelessWidget {
  const _AlbumEmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Text(
          message,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
