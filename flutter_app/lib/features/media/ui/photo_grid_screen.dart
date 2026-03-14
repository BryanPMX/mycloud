import 'package:flutter/material.dart';

import '../../../core/network/api_client.dart';
import '../../../shared/utils/date_formatter.dart';
import '../../../shared/utils/file_size_formatter.dart';
import '../../comments/domain/comment.dart';
import '../../comments/providers/comment_provider.dart';
import '../domain/media.dart';
import '../providers/media_list_provider.dart';

class PhotoGridScreen extends StatelessWidget {
  const PhotoGridScreen({
    super.key,
    required this.mediaProvider,
    required this.commentProvider,
    required this.apiClient,
  });

  final MediaListProvider mediaProvider;
  final CommentProvider commentProvider;
  final ApiClient apiClient;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: mediaProvider,
      builder: (context, _) {
        final theme = Theme.of(context);
        final items = mediaProvider.visibleItems;
        final selectedMedia = mediaProvider.selectedMedia;

        return LayoutBuilder(
          builder: (context, constraints) {
            final showDetailPanel =
                constraints.maxWidth >= 1120 && selectedMedia != null;

            return SingleChildScrollView(
              key: const ValueKey<String>('photo-grid-screen'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Wrap(
                        spacing: 16,
                        runSpacing: 16,
                        alignment: WrapAlignment.spaceBetween,
                        children: [
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 520),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Library ready for /media, /media/search, and presigned thumbnail reads.',
                                  style: theme.textTheme.titleLarge,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'The cards below are seeded to match the live API contracts. The next step is swapping them to real GET /media data and GET /media/:id/thumb reads.',
                                  style: theme.textTheme.bodyLarge?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              _MetricChip(
                                icon: Icons.task_alt_rounded,
                                label: '${mediaProvider.readyCount} ready',
                              ),
                              _MetricChip(
                                icon: Icons.hourglass_top_rounded,
                                label:
                                    '${mediaProvider.pendingItems.length} processing',
                              ),
                              _MetricChip(
                                icon: Icons.cloud_download_outlined,
                                label: apiClient.mediaListUri().path,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SizedBox(
                        width: 320,
                        child: TextField(
                          onChanged: mediaProvider.updateQuery,
                          decoration: const InputDecoration(
                            hintText: 'Search filenames or mime types',
                            prefixIcon: Icon(Icons.search_rounded),
                          ),
                        ),
                      ),
                      FilterChip(
                        selected: mediaProvider.favoritesOnly,
                        onSelected: (_) => mediaProvider.toggleFavoritesOnly(),
                        label: const Text('Favorites only'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  if (showDetailPanel)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 5,
                          child: _MediaGrid(
                            items: items,
                            onSelect: mediaProvider.selectMedia,
                            onFavoriteToggle: mediaProvider.toggleFavorite,
                            selectedMediaId: selectedMedia.id,
                          ),
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          flex: 3,
                          child: _DetailPanel(
                            media: selectedMedia,
                            comments: commentProvider.commentsFor(
                              selectedMedia.id,
                            ),
                            apiClient: apiClient,
                          ),
                        ),
                      ],
                    )
                  else ...[
                    _MediaGrid(
                      items: items,
                      onSelect: mediaProvider.selectMedia,
                      onFavoriteToggle: mediaProvider.toggleFavorite,
                      selectedMediaId: selectedMedia?.id,
                    ),
                    if (selectedMedia != null) ...[
                      const SizedBox(height: 20),
                      _DetailPanel(
                        media: selectedMedia,
                        comments: commentProvider.commentsFor(selectedMedia.id),
                        apiClient: apiClient,
                      ),
                    ],
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _MediaGrid extends StatelessWidget {
  const _MediaGrid({
    required this.items,
    required this.onSelect,
    required this.onFavoriteToggle,
    required this.selectedMediaId,
  });

  final List<Media> items;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onFavoriteToggle;
  final String? selectedMediaId;

  @override
  Widget build(BuildContext context) {
    final columns = _gridColumns(MediaQuery.sizeOf(context).width);

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 0.92,
      ),
      itemBuilder: (context, index) {
        final media = items[index];
        final isSelected = selectedMediaId == media.id;
        return _MediaCard(
          media: media,
          selected: isSelected,
          onSelect: () => onSelect(media.id),
          onFavoriteToggle: () => onFavoriteToggle(media.id),
        );
      },
    );
  }

  int _gridColumns(double width) {
    if (width >= 1500) {
      return 4;
    }
    if (width >= 1000) {
      return 3;
    }
    if (width >= 680) {
      return 2;
    }
    return 1;
  }
}

class _MediaCard extends StatelessWidget {
  const _MediaCard({
    required this.media,
    required this.selected,
    required this.onSelect,
    required this.onFavoriteToggle,
  });

  final Media media;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onFavoriteToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = switch (media.status) {
      MediaStatus.ready => theme.colorScheme.primary,
      MediaStatus.pending => theme.colorScheme.secondary,
      MediaStatus.failed => theme.colorScheme.error,
    };

    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: onSelect,
      child: Card(
        shape: RoundedRectangleBorder(
          side: selected
              ? BorderSide(color: theme.colorScheme.primary, width: 2)
              : BorderSide.none,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    gradient: LinearGradient(
                      colors: [
                        theme.colorScheme.primaryContainer,
                        theme.colorScheme.secondaryContainer,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              media.isVideo
                                  ? Icons.videocam_rounded
                                  : Icons.photo_camera_back_rounded,
                              size: 22,
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: statusColor.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                media.status.name,
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: statusColor,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const Spacer(),
                        Text(
                          media.isVideo ? 'Video' : 'Photo',
                          style: theme.textTheme.labelLarge,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          media.filename,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleLarge,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  _TinyBadge(label: FileSizeFormatter.compact(media.sizeBytes)),
                  _TinyBadge(label: '${media.width}×${media.height}'),
                  if (media.isVideo)
                    _TinyBadge(label: '${media.durationSecs}s'),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      DateFormatter.relative(media.uploadedAt),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: onFavoriteToggle,
                    icon: Icon(
                      media.isFavorite
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailPanel extends StatelessWidget {
  const _DetailPanel({
    required this.media,
    required this.comments,
    required this.apiClient,
  });

  final Media media;
  final List<Comment> comments;
  final ApiClient apiClient;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(media.filename, style: theme.textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              'Mapped to the current API contract including status, favorites, timestamps, and presigned-read endpoints.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            _SpecRow(
              label: 'Upload',
              value: DateFormatter.mediumDateTime(media.uploadedAt),
            ),
            _SpecRow(
              label: 'Taken',
              value: media.takenAt == null
                  ? 'Unknown'
                  : DateFormatter.mediumDateTime(media.takenAt!),
            ),
            _SpecRow(label: 'Mime', value: media.mimeType),
            _SpecRow(
              label: 'Thumb endpoint',
              value: apiClient.mediaThumbUri(media.id).path,
            ),
            _SpecRow(
              label: 'Download endpoint',
              value: apiClient.mediaDownloadUri(media.id).path,
            ),
            const SizedBox(height: 20),
            Text(
              'Recent implementation notes',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            ...comments.map(
              (comment) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    color: theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.45),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        comment.author.displayName,
                        style: theme.textTheme.labelLarge,
                      ),
                      const SizedBox(height: 4),
                      Text(comment.body),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(avatar: Icon(icon, size: 18), label: Text(label));
  }
}

class _TinyBadge extends StatelessWidget {
  const _TinyBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: theme.textTheme.labelMedium),
    );
  }
}

class _SpecRow extends StatelessWidget {
  const _SpecRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
