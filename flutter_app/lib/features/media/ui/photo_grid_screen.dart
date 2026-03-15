import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/network/api_client.dart';
import '../../../core/websocket/upload_progress_hub.dart';
import '../../../shared/utils/date_formatter.dart';
import '../../../shared/utils/file_size_formatter.dart';
import '../../comments/domain/comment.dart';
import '../../comments/providers/comment_provider.dart';
import '../domain/media.dart';
import '../domain/upload_task.dart';
import '../providers/media_list_provider.dart';
import '../providers/media_upload_provider.dart';

class PhotoGridScreen extends StatelessWidget {
  const PhotoGridScreen({
    super.key,
    required this.mediaProvider,
    required this.mediaUploadProvider,
    required this.commentProvider,
    required this.apiClient,
    required this.uploadProgressHub,
  });

  final MediaListProvider mediaProvider;
  final MediaUploadProvider mediaUploadProvider;
  final CommentProvider commentProvider;
  final ApiClient apiClient;
  final UploadProgressHub uploadProgressHub;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[
        mediaProvider,
        mediaUploadProvider,
        commentProvider,
        uploadProgressHub,
      ]),
      builder: (context, _) {
        final theme = Theme.of(context);
        final items = mediaProvider.visibleItems;
        final selectedMedia = mediaProvider.selectedMedia;
        final activeUploads = mediaUploadProvider.tasks
            .where((task) => !task.isTerminal)
            .length;

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
                            constraints: const BoxConstraints(maxWidth: 620),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Live media library',
                                  style: theme.textTheme.titleLarge,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'This surface now reads the real /media and /media/search endpoints, keeps favorites in sync, uploads files through the multipart API, and reflects worker processing via /ws/progress.',
                                  style: theme.textTheme.bodyLarge?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                if (mediaProvider.errorMessage != null) ...[
                                  const SizedBox(height: 12),
                                  Text(
                                    mediaProvider.errorMessage!,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: theme.colorScheme.error,
                                    ),
                                  ),
                                ],
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
                                icon: mediaProvider.isLoading
                                    ? Icons.sync_rounded
                                    : Icons.cloud_done_rounded,
                                label: mediaProvider.isLoading
                                    ? 'Refreshing'
                                    : '$activeUploads uploads',
                              ),
                              _MetricChip(
                                icon: uploadProgressHub.isConnected
                                    ? Icons.wifi_tethering_rounded
                                    : Icons.portable_wifi_off_rounded,
                                label:
                                    'Progress ${uploadProgressHub.statusLabel}',
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
                            hintText: 'Search filenames or metadata',
                            prefixIcon: Icon(Icons.search_rounded),
                          ),
                        ),
                      ),
                      FilterChip(
                        selected: mediaProvider.favoritesOnly,
                        onSelected: (_) => mediaProvider.toggleFavoritesOnly(),
                        label: const Text('Favorites only'),
                      ),
                      OutlinedButton.icon(
                        onPressed: mediaProvider.isLoading
                            ? null
                            : () {
                                mediaProvider.load();
                              },
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Refresh'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _UploadPanel(
                    mediaUploadProvider: mediaUploadProvider,
                    uploadProgressHub: uploadProgressHub,
                    apiClient: apiClient,
                  ),
                  const SizedBox(height: 20),
                  if (mediaProvider.isLoading && items.isEmpty)
                    const _LoadingState()
                  else if (items.isEmpty)
                    _EmptyState(errorMessage: mediaProvider.errorMessage)
                  else if (showDetailPanel)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 5,
                          child: _MediaGrid(
                            items: items,
                            mediaProvider: mediaProvider,
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
                            commentsLoading: commentProvider.isLoading &&
                                commentProvider.activeMediaId ==
                                    selectedMedia.id,
                            commentsError: commentProvider.activeMediaId ==
                                    selectedMedia.id
                                ? commentProvider.errorMessage
                                : null,
                            apiClient: apiClient,
                            thumbUrl: mediaProvider.thumbnailUrlFor(
                              selectedMedia.id,
                            ),
                          ),
                        ),
                      ],
                    )
                  else ...[
                    _MediaGrid(
                      items: items,
                      mediaProvider: mediaProvider,
                      onSelect: mediaProvider.selectMedia,
                      onFavoriteToggle: mediaProvider.toggleFavorite,
                      selectedMediaId: selectedMedia?.id,
                    ),
                    if (selectedMedia != null) ...[
                      const SizedBox(height: 20),
                      _DetailPanel(
                        media: selectedMedia,
                        comments: commentProvider.commentsFor(selectedMedia.id),
                        commentsLoading: commentProvider.isLoading &&
                            commentProvider.activeMediaId == selectedMedia.id,
                        commentsError:
                            commentProvider.activeMediaId == selectedMedia.id
                                ? commentProvider.errorMessage
                                : null,
                        apiClient: apiClient,
                        thumbUrl: mediaProvider.thumbnailUrlFor(
                          selectedMedia.id,
                        ),
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

class _UploadPanel extends StatelessWidget {
  const _UploadPanel({
    required this.mediaUploadProvider,
    required this.uploadProgressHub,
    required this.apiClient,
  });

  final MediaUploadProvider mediaUploadProvider;
  final UploadProgressHub uploadProgressHub;
  final ApiClient apiClient;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tasks = mediaUploadProvider.tasks.take(4).toList(growable: false);
    final activeCount = mediaUploadProvider.tasks
        .where((task) => !task.isTerminal)
        .length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 16,
              runSpacing: 16,
              alignment: WrapAlignment.spaceBetween,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Multipart uploads',
                        style: theme.textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Choose files from the browser, stream them directly to storage with presigned part URLs, then wait for the worker to scan and generate thumbnails before the items settle into the library.',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (mediaUploadProvider.errorMessage != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          mediaUploadProvider.errorMessage!,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                      ],
                      if (uploadProgressHub.errorMessage != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          uploadProgressHub.errorMessage!,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _MetricChip(
                      icon: Icons.upload_file_rounded,
                      label: '$activeCount active',
                    ),
                    _MetricChip(
                      icon: uploadProgressHub.isConnected
                          ? Icons.wifi_tethering_rounded
                          : Icons.portable_wifi_off_rounded,
                      label: '/ws/progress ${uploadProgressHub.statusLabel}',
                    ),
                    _MetricChip(
                      icon: Icons.route_rounded,
                      label: apiClient.uploadInitUri().path,
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: mediaUploadProvider.isPickingFiles ||
                          !mediaUploadProvider.canPickFiles
                      ? null
                      : () {
                          mediaUploadProvider.pickAndUpload();
                        },
                  icon: mediaUploadProvider.isPickingFiles
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.upload_rounded),
                  label: Text(
                    mediaUploadProvider.isPickingFiles
                        ? 'Choosing files...'
                        : 'Upload from device',
                  ),
                ),
                if (!uploadProgressHub.isConnected &&
                    mediaUploadProvider.tasks.isNotEmpty)
                  OutlinedButton.icon(
                    onPressed: uploadProgressHub.retryNow,
                    icon: const Icon(Icons.sync_rounded),
                    label: const Text('Reconnect progress'),
                  ),
                Text(
                  mediaUploadProvider.pickerHint,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (tasks.isEmpty)
              Text(
                'No uploads started yet.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else
              ...tasks.map(
                (task) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _UploadTaskRow(
                    task: task,
                    onCancel: () {
                      mediaUploadProvider.cancelUpload(task.localId);
                    },
                    onDismiss: () {
                      mediaUploadProvider.dismissUpload(task.localId);
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _UploadTaskRow extends StatelessWidget {
  const _UploadTaskRow({
    required this.task,
    required this.onCancel,
    required this.onDismiss,
  });

  final MediaUploadTask task;
  final VoidCallback onCancel;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(task.filename, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      '${FileSizeFormatter.compact(task.sizeBytes)} • ${DateFormatter.relative(task.createdAt)}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              _TinyBadge(label: task.stage.label),
              if (task.canCancel)
                IconButton(
                  onPressed: onCancel,
                  icon: const Icon(Icons.close_rounded),
                  tooltip: 'Cancel upload',
                )
              else if (task.canDismiss)
                IconButton(
                  onPressed: onDismiss,
                  icon: const Icon(Icons.check_rounded),
                  tooltip: 'Dismiss upload',
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (task.stage == MediaUploadStage.processing)
            const LinearProgressIndicator()
          else
            LinearProgressIndicator(value: task.progress.clamp(0, 1)),
          const SizedBox(height: 10),
          Text(
            task.message ?? _defaultUploadMessage(task),
            style: theme.textTheme.bodyMedium,
          ),
          if (task.totalParts > 0) ...[
            const SizedBox(height: 6),
            Text(
              '${task.completedParts} of ${task.totalParts} parts uploaded',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _defaultUploadMessage(MediaUploadTask task) {
    switch (task.stage) {
      case MediaUploadStage.queued:
        return 'Waiting to start.';
      case MediaUploadStage.initializing:
        return 'Creating the multipart upload session.';
      case MediaUploadStage.uploading:
        return 'Uploading file parts directly to storage.';
      case MediaUploadStage.processing:
        return 'Waiting for virus scan, metadata extraction, and thumbnails.';
      case MediaUploadStage.complete:
        return 'Upload finished and processing is complete.';
      case MediaUploadStage.failed:
        return 'Upload failed.';
      case MediaUploadStage.cancelled:
        return 'Upload cancelled.';
    }
  }
}

class _MediaGrid extends StatelessWidget {
  const _MediaGrid({
    required this.items,
    required this.mediaProvider,
    required this.onSelect,
    required this.onFavoriteToggle,
    required this.selectedMediaId,
  });

  final List<Media> items;
  final MediaListProvider mediaProvider;
  final ValueChanged<String> onSelect;
  final Future<void> Function(String mediaId) onFavoriteToggle;
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
          mediaProvider: mediaProvider,
          thumbnailUrl: mediaProvider.thumbnailUrlFor(media.id),
          selected: isSelected,
          onSelect: () => onSelect(media.id),
          onFavoriteToggle: () {
            unawaited(onFavoriteToggle(media.id));
          },
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
    required this.mediaProvider,
    required this.thumbnailUrl,
    required this.selected,
    required this.onSelect,
    required this.onFavoriteToggle,
  });

  final Media media;
  final MediaListProvider mediaProvider;
  final String? thumbnailUrl;
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
                child: _MediaPreview(
                  media: media,
                  mediaProvider: mediaProvider,
                  thumbnailUrl: thumbnailUrl,
                  statusColor: statusColor,
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
                    _TinyBadge(label: '${media.durationSecs.ceil()}s'),
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

class _MediaPreview extends StatefulWidget {
  const _MediaPreview({
    required this.media,
    required this.mediaProvider,
    required this.thumbnailUrl,
    required this.statusColor,
  });

  final Media media;
  final MediaListProvider mediaProvider;
  final String? thumbnailUrl;
  final Color statusColor;

  @override
  State<_MediaPreview> createState() => _MediaPreviewState();
}

class _MediaPreviewState extends State<_MediaPreview> {
  @override
  void initState() {
    super.initState();
    unawaited(widget.mediaProvider.ensureThumbnailLoaded(widget.media));
  }

  @override
  void didUpdateWidget(covariant _MediaPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.media.id != widget.media.id ||
        oldWidget.thumbnailUrl != widget.thumbnailUrl) {
      unawaited(widget.mediaProvider.ensureThumbnailLoaded(widget.media));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: widget.thumbnailUrl == null
            ? LinearGradient(
                colors: <Color>[
                  theme.colorScheme.primaryContainer,
                  theme.colorScheme.secondaryContainer,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        color: widget.thumbnailUrl == null
            ? null
            : theme.colorScheme.surfaceContainerHighest,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (widget.thumbnailUrl != null)
              Image.network(
                widget.thumbnailUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _PreviewFallback(
                  media: widget.media,
                  statusColor: widget.statusColor,
                ),
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) {
                    return child;
                  }

                  return _PreviewFallback(
                    media: widget.media,
                    statusColor: widget.statusColor,
                  );
                },
              )
            else
              _PreviewFallback(
                media: widget.media,
                statusColor: widget.statusColor,
              ),
            Positioned(
              left: 12,
              right: 12,
              top: 12,
              child: Row(
                children: [
                  Icon(
                    widget.media.isVideo
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
                      color: widget.statusColor.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      widget.media.status.name,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: widget.statusColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.media.isVideo ? 'Video' : 'Photo',
                    style: theme.textTheme.labelLarge,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    widget.media.filename,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleLarge,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewFallback extends StatelessWidget {
  const _PreviewFallback({required this.media, required this.statusColor});

  final Media media;
  final Color statusColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
      padding: const EdgeInsets.all(18),
      child: Align(
        alignment: Alignment.bottomLeft,
        child: Row(
          children: [
            Icon(
              media.isVideo
                  ? Icons.videocam_rounded
                  : Icons.photo_camera_back_rounded,
              color: statusColor,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                media.status == MediaStatus.ready
                    ? 'Resolving thumbnail...'
                    : 'Waiting for processing...',
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailPanel extends StatelessWidget {
  const _DetailPanel({
    required this.media,
    required this.comments,
    required this.commentsLoading,
    required this.commentsError,
    required this.apiClient,
    required this.thumbUrl,
  });

  final Media media;
  final List<Comment> comments;
  final bool commentsLoading;
  final String? commentsError;
  final ApiClient apiClient;
  final String? thumbUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (thumbUrl != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: AspectRatio(
                  aspectRatio: media.aspectRatio,
                  child: Image.network(
                    thumbUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            Text(media.filename, style: theme.textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              'Mapped directly to the current API contract, including status, favorites, timestamps, comments, and presigned-read endpoints.',
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
            Text('Comments', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            if (commentsLoading)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: LinearProgressIndicator(),
              ),
            if (commentsError != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  commentsError!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            if (!commentsLoading && comments.isEmpty)
              Text(
                'No comments yet.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
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

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: const [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('Loading media from the API...'),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.errorMessage});

  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Icon(Icons.photo_library_outlined, size: 40),
            const SizedBox(height: 12),
            Text(
              errorMessage ?? 'No media matched the current filters.',
              style: theme.textTheme.bodyLarge,
              textAlign: TextAlign.center,
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
