import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/connectivity/connectivity_service.dart';
import '../../../core/network/api_client.dart';
import '../../../core/websocket/upload_progress_hub.dart';
import '../../../shared/widgets/user_avatar.dart';
import '../../../shared/widgets/vault_ui.dart';
import '../../../shared/utils/date_formatter.dart';
import '../../../shared/utils/file_size_formatter.dart';
import '../../auth/domain/user.dart';
import '../../comments/domain/comment.dart';
import '../../comments/providers/comment_provider.dart';
import '../../directory/providers/family_directory_provider.dart';
import '../domain/media.dart';
import '../domain/upload_task.dart';
import '../providers/media_list_provider.dart';
import '../providers/media_upload_provider.dart';

class PhotoGridScreen extends StatefulWidget {
  const PhotoGridScreen({
    super.key,
    this.onOpen,
    this.onOpenTrash,
    required this.mediaProvider,
    required this.mediaUploadProvider,
    required this.commentProvider,
    required this.familyDirectoryProvider,
    required this.apiClient,
    required this.uploadProgressHub,
    required this.currentUser,
    required this.connectivityService,
  });

  final void Function(Media)? onOpen;
  final VoidCallback? onOpenTrash;
  final MediaListProvider mediaProvider;
  final MediaUploadProvider mediaUploadProvider;
  final CommentProvider commentProvider;
  final FamilyDirectoryProvider familyDirectoryProvider;
  final ApiClient apiClient;
  final UploadProgressHub uploadProgressHub;
  final User? currentUser;
  final ConnectivityService connectivityService;

  @override
  State<PhotoGridScreen> createState() => _PhotoGridScreenState();
}

class _PhotoGridScreenState extends State<PhotoGridScreen> {
  String _filter = 'all';
  bool _newest = true;

  void _uploads() {
    showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (context) => SafeArea(
            child: ConstrainedBox(
                constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * .85),
                child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
                    child: AnimatedBuilder(
                        animation: Listenable.merge([
                          widget.mediaUploadProvider,
                          widget.uploadProgressHub,
                          widget.connectivityService
                        ]),
                        builder: (context, _) => _UploadPanel(
                            mediaUploadProvider: widget.mediaUploadProvider,
                            uploadProgressHub: widget.uploadProgressHub,
                            apiClient: widget.apiClient,
                            connectivityService:
                                widget.connectivityService))))));
  }

  void _details(Media media) {
    widget.mediaProvider.selectMedia(media.id);
    showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (context) => SafeArea(
            child: SizedBox(
                height: MediaQuery.sizeOf(context).height * .78,
                child: AnimatedBuilder(
                    animation: Listenable.merge(
                        [widget.commentProvider, widget.mediaProvider]),
                    builder: (context, _) => SingleChildScrollView(
                        padding: EdgeInsets.fromLTRB(18, 0, 18,
                            MediaQuery.viewInsetsOf(context).bottom + 24),
                        child: _DetailPanel(
                            media: media,
                            comments:
                                widget.commentProvider.commentsFor(media.id),
                            commentsLoading: widget.commentProvider.isLoading,
                            commentsError: widget.commentProvider.errorMessage,
                            apiClient: widget.apiClient,
                            thumbUrl:
                                widget.mediaProvider.thumbnailUrlFor(media.id),
                            commentProvider: widget.commentProvider,
                            familyDirectoryProvider:
                                widget.familyDirectoryProvider,
                            currentUser: widget.currentUser))))));
  }

  Widget _searchField() => TextField(
      key: const ValueKey('vault-search'),
      onChanged: widget.mediaProvider.updateQuery,
      decoration: const InputDecoration(
          hintText: 'Search your memories',
          prefixIcon: Icon(Icons.search_rounded, size: 21)));

  Widget _filterBar() {
    final provider = widget.mediaProvider;
    return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (final option in const [
            ('all', 'All'),
            ('photos', 'Photos'),
            ('videos', 'Videos')
          ]) ...[
            VaultPill(option.$2,
                selected: _filter == option.$1 && !provider.favoritesOnly,
                onTap: () {
              if (provider.favoritesOnly) provider.toggleFavoritesOnly();
              setState(() => _filter = option.$1);
            }),
            const SizedBox(width: 8)
          ],
          VaultPill('Favorites',
              icon: Icons.favorite_border_rounded,
              selected: provider.favoritesOnly, onTap: () {
            provider.toggleFavoritesOnly();
            setState(() => _filter = 'all');
          })
        ]));
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: Listenable.merge([
        widget.mediaProvider,
        widget.mediaUploadProvider,
        widget.connectivityService
      ]),
      builder: (context, _) {
        final theme = Theme.of(context);
        final colors = theme.colorScheme;
        final provider = widget.mediaProvider;
        final all = provider.visibleItems;
        final items = all
            .where((m) => _filter == 'photos'
                ? !m.isVideo
                : _filter == 'videos'
                    ? m.isVideo
                    : true)
            .toList()
          ..sort((a, b) => _newest
              ? b.uploadedAt.compareTo(a.uploadedAt)
              : a.uploadedAt.compareTo(b.uploadedAt));
        final active =
            widget.mediaUploadProvider.tasks.where((t) => !t.isTerminal).length;
        return LayoutBuilder(builder: (context, constraints) {
          final mobile = constraints.maxWidth < 600;
          return RefreshIndicator(
              onRefresh: provider.load,
              child: SingleChildScrollView(
                  key: const ValueKey<String>('photo-grid-screen'),
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        VaultEnter(
                            child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                              Expanded(
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                    Text('Your vault',
                                        style: theme.textTheme.headlineMedium),
                                    const SizedBox(height: 7),
                                    Text('Yours to keep. Yours to share.',
                                        style: TextStyle(
                                            color: colors.onSurfaceVariant,
                                            fontSize: mobile ? 12 : 14)),
                                  ])),
                              const SizedBox(width: 12),
                              if (mobile)
                                IconButton.filled(
                                    key: const ValueKey('open-upload'),
                                    tooltip: 'Add memories',
                                    onPressed: _uploads,
                                    style: IconButton.styleFrom(
                                        backgroundColor: colors.primary,
                                        foregroundColor: colors.onPrimary,
                                        minimumSize: const Size(48, 48)),
                                    icon: const Icon(Icons.add_rounded))
                              else
                                FilledButton.icon(
                                    key: const ValueKey('open-upload'),
                                    onPressed: _uploads,
                                    style: FilledButton.styleFrom(
                                        backgroundColor: colors.primary,
                                        foregroundColor: colors.onPrimary),
                                    icon:
                                        const Icon(Icons.add_rounded, size: 19),
                                    label: const Text('Add memories')),
                            ])),
                        const SizedBox(height: 20),
                        if (mobile) ...[
                          _searchField(),
                          const SizedBox(height: 16),
                          _filterBar()
                        ] else
                          Row(children: [
                            Expanded(child: _filterBar()),
                            const SizedBox(width: 20),
                            SizedBox(width: 275, child: _searchField())
                          ]),
                        const SizedBox(height: 12),
                        Row(children: [
                          Expanded(
                              child: Text(
                                  '${items.length} ${items.length == 1 ? 'memory' : 'memories'}',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: colors.onSurfaceVariant))),
                          PopupMenuButton<bool>(
                              tooltip: 'Sort memories',
                              onSelected: (value) =>
                                  setState(() => _newest = value),
                              itemBuilder: (_) => const [
                                    PopupMenuItem(
                                        value: true,
                                        child: Text('Newest first')),
                                    PopupMenuItem(
                                        value: false,
                                        child: Text('Oldest first'))
                                  ],
                              child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Row(children: [
                                    Text(
                                        _newest
                                            ? 'Newest first'
                                            : 'Oldest first',
                                        style: const TextStyle(fontSize: 11)),
                                    const SizedBox(width: 4),
                                    const Icon(
                                        Icons.keyboard_arrow_down_rounded,
                                        size: 16)
                                  ]))),
                          PopupMenuButton<String>(
                              tooltip: 'Vault options',
                              onSelected: (value) {
                                if (value == 'trash') {
                                  widget.onOpenTrash?.call();
                                } else {
                                  provider.load();
                                }
                              },
                              itemBuilder: (_) => [
                                    const PopupMenuItem(
                                        value: 'refresh',
                                        child: Text('Refresh memories')),
                                    if (widget.onOpenTrash != null)
                                      const PopupMenuItem(
                                          value: 'trash',
                                          child: Text('Recently deleted'))
                                  ]),
                        ]),
                        if (active > 0)
                          Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: InkWell(
                                  onTap: _uploads,
                                  child: Container(
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                          color: colors.primaryContainer,
                                          borderRadius:
                                              BorderRadius.circular(14)),
                                      child: Row(children: [
                                        const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2)),
                                        const SizedBox(width: 12),
                                        Expanded(
                                            child: Text(
                                                'Keeping $active ${active == 1 ? 'memory' : 'memories'} safe…',
                                                style: const TextStyle(
                                                    fontSize: 12))),
                                        const Icon(Icons.chevron_right_rounded,
                                            size: 18)
                                      ])))),
                        if (provider.errorMessage != null)
                          Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: Text(provider.errorMessage!,
                                  style: TextStyle(color: colors.error))),
                        if (provider.isLoading) const LinearProgressIndicator(),
                        const SizedBox(height: 8),
                        if (items.isEmpty && !provider.isLoading)
                          Padding(
                              padding: const EdgeInsets.symmetric(
                                  vertical: 65, horizontal: 16),
                              child: Center(
                                  child: Column(children: [
                                Icon(Icons.photo_library_outlined,
                                    size: 42, color: colors.secondary),
                                const SizedBox(height: 18),
                                Text(
                                    all.isEmpty
                                        ? 'Make room for your moments.'
                                        : 'Nothing here just yet.',
                                    style: theme.textTheme.titleLarge,
                                    textAlign: TextAlign.center),
                                const SizedBox(height: 8),
                                Text(
                                    all.isEmpty
                                        ? 'Add a few photos or videos. This space is only yours.'
                                        : 'Try a different filter or search.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        color: colors.onSurfaceVariant)),
                                if (all.isEmpty) ...[
                                  const SizedBox(height: 22),
                                  FilledButton(
                                      onPressed: _uploads,
                                      child:
                                          const Text('Add your first memory'))
                                ]
                              ])))
                        else
                          MemoryMasonry(
                              items: items,
                              builder: (media, index) => _VaultMemoryTile(
                                  media: media,
                                  provider: provider,
                                  onOpen: () {
                                    provider.selectMedia(media.id);
                                    if (media.status == MediaStatus.ready) {
                                      widget.onOpen?.call(media);
                                    } else {
                                      _details(media);
                                    }
                                  },
                                  onDetails: () => _details(media))),
                        if (provider.hasMore)
                          Center(
                              child: Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: OutlinedButton(
                                      onPressed: provider.isLoading
                                          ? null
                                          : provider.loadMore,
                                      child: const Text('More memories')))),
                        const SizedBox(height: 24),
                      ])));
        });
      });
}

class _VaultMemoryTile extends StatefulWidget {
  const _VaultMemoryTile(
      {required this.media,
      required this.provider,
      required this.onOpen,
      required this.onDetails});
  final Media media;
  final MediaListProvider provider;
  final VoidCallback onOpen;
  final VoidCallback onDetails;
  @override
  State<_VaultMemoryTile> createState() => _VaultMemoryTileState();
}

class _VaultMemoryTileState extends State<_VaultMemoryTile> {
  bool _hover = false;
  @override
  void initState() {
    super.initState();
    unawaited(widget.provider.ensureThumbnailLoaded(widget.media));
  }

  @override
  Widget build(BuildContext context) {
    final media = widget.media;
    final theme = Theme.of(context);
    final aspect =
        media.height > 0 ? (media.width / media.height).clamp(.62, 1.5) : .8;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      MouseRegion(
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: AnimatedScale(
              scale: _hover ? 1.018 : 1,
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              child: ClipRRect(
                  borderRadius: BorderRadius.circular(17),
                  child: AspectRatio(
                      aspectRatio: aspect,
                      child: Stack(fit: StackFit.expand, children: [
                        VaultImage(
                            url: widget.provider.thumbnailUrlFor(media.id),
                            label: media.filename,
                            onError: () => unawaited(widget.provider
                                .handleThumbnailLoadError(media))),
                        Positioned.fill(
                            child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                    key: ValueKey('open-memory-${media.id}'),
                                    onTap: widget.onOpen,
                                    onLongPress: widget.onDetails,
                                    child: Semantics(
                                        label: 'Open ${media.filename}',
                                        button: true,
                                        child: const SizedBox.expand())))),
                        if (media.isVideo || media.status != MediaStatus.ready)
                          Positioned(
                              left: 10,
                              top: 10,
                              child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 9, vertical: 6),
                                  decoration: BoxDecoration(
                                      color:
                                          Colors.black.withValues(alpha: .55),
                                      borderRadius: BorderRadius.circular(20)),
                                  child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                            media.isVideo
                                                ? Icons.play_arrow_rounded
                                                : Icons.schedule_rounded,
                                            color: Colors.white,
                                            size: 13),
                                        const SizedBox(width: 4),
                                        Text(
                                            media.status != MediaStatus.ready
                                                ? (media.status ==
                                                        MediaStatus.failed
                                                    ? 'Try again'
                                                    : 'Preparing')
                                                : '${media.durationSecs.ceil()}s',
                                            style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 10,
                                                fontWeight: FontWeight.w700))
                                      ]))),
                        Positioned(
                            right: 6,
                            top: 6,
                            child: IconButton(
                                key: ValueKey('favorite-${media.id}'),
                                tooltip: media.isFavorite
                                    ? 'Remove from favorites'
                                    : 'Save to favorites',
                                style: IconButton.styleFrom(
                                    backgroundColor:
                                        Colors.black.withValues(alpha: .22),
                                    foregroundColor: Colors.white,
                                    minimumSize: const Size(44, 44)),
                                onPressed: () =>
                                    widget.provider.toggleFavorite(media.id),
                                icon: Icon(
                                    media.isFavorite
                                        ? Icons.favorite_rounded
                                        : Icons.favorite_border_rounded,
                                    size: 19))),
                      ]))))),
      Row(children: [
        Expanded(
            child: Text(
                DateFormatter.mediumDate(media.takenAt ?? media.uploadedAt),
                style: TextStyle(
                    fontSize: 10, color: theme.colorScheme.onSurfaceVariant),
                maxLines: 1,
                overflow: TextOverflow.ellipsis)),
        IconButton(
            key: ValueKey('memory-details-${media.id}'),
            tooltip: 'Details and comments',
            onPressed: widget.onDetails,
            icon: const Icon(Icons.more_horiz_rounded, size: 18))
      ]),
    ]);
  }
}

class _UploadPanel extends StatelessWidget {
  const _UploadPanel({
    required this.mediaUploadProvider,
    required this.uploadProgressHub,
    required this.apiClient,
    required this.connectivityService,
  });

  final MediaUploadProvider mediaUploadProvider;
  final UploadProgressHub uploadProgressHub;
  final ApiClient apiClient;
  final ConnectivityService connectivityService;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tasks = mediaUploadProvider.tasks.take(4).toList(growable: false);
    final activeCount =
        mediaUploadProvider.tasks.where((task) => !task.isTerminal).length;

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
                        'Add memories',
                        style: theme.textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Choose photos or videos up to 512 MB each. Keep Mynube open until uploading finishes; we’ll prepare previews for you.',
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
                      if (connectivityService.isOffline) ...[
                        const SizedBox(height: 12),
                        Text(
                          connectivityService.statusMessage,
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
                    if (activeCount > 0)
                      _MetricChip(
                        icon: Icons.upload_file_rounded,
                        label: '$activeCount active',
                      ),
                    if (activeCount > 0 && !uploadProgressHub.isConnected)
                      _MetricChip(
                        icon: uploadProgressHub.isConnected
                            ? Icons.wifi_tethering_rounded
                            : Icons.portable_wifi_off_rounded,
                        label: 'Reconnecting updates',
                      ),
                    if (connectivityService.status ==
                        ConnectivityStatus.offline)
                      _MetricChip(
                        icon: switch (connectivityService.status) {
                          ConnectivityStatus.online => Icons.wifi_rounded,
                          ConnectivityStatus.offline =>
                            Icons.portable_wifi_off_rounded,
                          ConnectivityStatus.unknown => Icons.sync_rounded,
                        },
                        label: connectivityService.statusLabel,
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
                  key: const ValueKey<String>('media-upload-start'),
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
                    key: const ValueKey<String>('media-progress-reconnect'),
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
            if (tasks.isNotEmpty)
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
              '${(task.progress * 100).round()}% uploaded',
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
        return 'Preparing your upload.';
      case MediaUploadStage.uploading:
        return 'Uploading your file.';
      case MediaUploadStage.processing:
        return 'Checking your file and preparing previews.';
      case MediaUploadStage.complete:
        return 'Upload finished and processing is complete.';
      case MediaUploadStage.failed:
        return 'Upload failed.';
      case MediaUploadStage.cancelled:
        return 'Upload cancelled.';
    }
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
    required this.commentProvider,
    required this.familyDirectoryProvider,
    required this.currentUser,
  });

  final Media media;
  final List<Comment> comments;
  final bool commentsLoading;
  final String? commentsError;
  final ApiClient apiClient;
  final String? thumbUrl;
  final CommentProvider commentProvider;
  final FamilyDirectoryProvider familyDirectoryProvider;
  final User? currentUser;

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
                  child: VaultImage(
                    url: thumbUrl!,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            Text(media.filename, style: theme.textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              'The story behind this memory.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            _SpecRow(
              label: 'Added',
              value: DateFormatter.mediumDateTime(media.uploadedAt),
            ),
            _SpecRow(
              label: 'Taken',
              value: media.takenAt == null
                  ? 'Unknown'
                  : DateFormatter.mediumDateTime(media.takenAt!),
            ),
            _SpecRow(label: 'File type', value: media.mimeType),
            const SizedBox(height: 20),
            Text('Comments', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            if (currentUser != null) ...[
              _CommentComposer(
                key: ValueKey<String>('comment-composer-${media.id}'),
                mediaId: media.id,
                commentProvider: commentProvider,
              ),
              const SizedBox(height: 16),
            ],
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
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          UserAvatar(
                            userId: comment.author.id,
                            displayName: comment.author.displayName,
                            initialAvatarUrl: comment.author.avatarUrl,
                            directoryProvider: familyDirectoryProvider,
                            radius: 16,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  comment.author.displayName,
                                  style: theme.textTheme.labelLarge,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  DateFormatter.relative(comment.createdAt),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (_canDeleteComment(comment))
                            IconButton(
                              onPressed:
                                  commentProvider.isDeletingComment(comment.id)
                                      ? null
                                      : () {
                                          unawaited(
                                            commentProvider.deleteComment(
                                              media.id,
                                              comment.id,
                                            ),
                                          );
                                        },
                              icon: commentProvider
                                      .isDeletingComment(comment.id)
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.delete_outline_rounded),
                              tooltip: 'Delete comment',
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
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

  bool _canDeleteComment(Comment comment) {
    final user = currentUser;
    if (user == null) {
      return false;
    }

    return user.isAdmin || user.id == comment.author.id;
  }
}

class _CommentComposer extends StatefulWidget {
  const _CommentComposer({
    super.key,
    required this.mediaId,
    required this.commentProvider,
  });

  final String mediaId;
  final CommentProvider commentProvider;

  @override
  State<_CommentComposer> createState() => _CommentComposerState();
}

class _CommentComposerState extends State<_CommentComposer> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController()..addListener(_handleChanged);
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_handleChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canSubmit = _controller.text.trim().isNotEmpty &&
        !widget.commentProvider.isSubmitting;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          key: ValueKey<String>('comment-input-${widget.mediaId}'),
          controller: _controller,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Write a comment',
            hintText: 'Add context for the rest of the family.',
          ),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            key: ValueKey<String>('comment-submit-${widget.mediaId}'),
            onPressed: canSubmit ? _submit : null,
            icon: widget.commentProvider.isSubmitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send_rounded),
            label: Text(
              widget.commentProvider.isSubmitting
                  ? 'Posting...'
                  : 'Post comment',
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    final didPost = await widget.commentProvider.addComment(
      widget.mediaId,
      _controller.text,
    );
    if (didPost && mounted) {
      _controller.clear();
    }
  }

  void _handleChanged() {
    setState(() {});
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
