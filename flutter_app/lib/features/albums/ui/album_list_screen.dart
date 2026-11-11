import 'dart:async';

import 'package:flutter/material.dart';

import '../../../shared/widgets/user_avatar.dart';
import '../../../shared/widgets/vault_ui.dart';
import '../../../shared/utils/date_formatter.dart';
import '../../directory/domain/directory_user.dart';
import '../../directory/providers/family_directory_provider.dart';
import '../../media/domain/media.dart';
import '../../feed/providers/feed_provider.dart';
import '../../feed/ui/media_viewer.dart';
import '../../media/providers/media_list_provider.dart';
import '../domain/album.dart';
import '../domain/album_share.dart';
import '../providers/album_provider.dart';

class AlbumListScreen extends StatelessWidget {
  const AlbumListScreen({
    super.key,
    required this.albumProvider,
    required this.mediaProvider,
    required this.familyDirectoryProvider,
    required this.currentUserId,
    this.feedProvider,
  });

  final AlbumProvider albumProvider;
  final MediaListProvider mediaProvider;
  final FamilyDirectoryProvider familyDirectoryProvider;
  final String currentUserId;
  final FeedProvider? feedProvider;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: Listenable.merge([albumProvider, mediaProvider]),
      builder: (context, _) {
        final theme = Theme.of(context);
        final owned = albumProvider.ownedAlbums;
        final shared = albumProvider.sharedAlbums;
        Widget collection(Album album) => _AlbumCard(
            album: album,
            albumProvider: albumProvider,
            mediaProvider: mediaProvider,
            canManage: albumProvider.canManage(album),
            isSaving: albumProvider.isSavingAlbum(album.id),
            isDeleting: albumProvider.isDeletingAlbum(album.id),
            onViewItems: () => _showAlbumMediaDialog(context, album: album),
            onManageShares: () => _showAlbumSharesDialog(context, album: album),
            onEdit: () => _showAlbumEditorDialog(context,
                albumProvider: albumProvider, album: album),
            onDelete: () => _showDeleteAlbumDialog(context,
                albumProvider: albumProvider, album: album));
        Widget grid(List<Album> albums) =>
            LayoutBuilder(builder: (context, constraints) {
              final columns = constraints.maxWidth < 500
                  ? 2
                  : constraints.maxWidth < 900
                      ? 3
                      : 4;
              final width =
                  (constraints.maxWidth - (columns - 1) * 16) / columns;
              return Wrap(
                  spacing: 16,
                  runSpacing: 24,
                  children: albums
                      .map((album) =>
                          SizedBox(width: width, child: collection(album)))
                      .toList());
            });
        return SingleChildScrollView(
            key: const ValueKey<String>('album-list-screen'),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const VaultEyebrow('Keep the good things together'),
              const SizedBox(height: 8),
              Text('Collections', style: theme.textTheme.headlineMedium),
              const SizedBox(height: 8),
              Text('Little worlds, made by you.',
                  style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
              const SizedBox(height: 24),
              Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    FilledButton.icon(
                        key: const ValueKey<String>('create-album-button'),
                        onPressed: albumProvider.isCreating
                            ? null
                            : () => _showAlbumEditorDialog(context,
                                albumProvider: albumProvider),
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('New collection')),
                    IconButton(
                        tooltip: 'Refresh collections',
                        onPressed:
                            albumProvider.isLoading ? null : albumProvider.load,
                        icon: const Icon(Icons.refresh_rounded, size: 20))
                  ]),
              if (albumProvider.errorMessage != null)
                Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(albumProvider.errorMessage!,
                        style: TextStyle(color: theme.colorScheme.error))),
              const SizedBox(height: 30),
              if (albumProvider.isLoading && !albumProvider.hasLoaded)
                const LinearProgressIndicator(),
              Text('Made by you', style: theme.textTheme.titleMedium),
              const SizedBox(height: 16),
              if (owned.isEmpty)
                const _AlbumEmptyState(
                    message:
                        'Gather a few favorites into your first collection.')
              else
                grid(owned),
              const SizedBox(height: 32),
              Text('Shared with you', style: theme.textTheme.titleMedium),
              const SizedBox(height: 16),
              if (shared.isEmpty)
                const _AlbumEmptyState(
                    message:
                        'Collections from your circle will find a home here.')
              else
                grid(shared),
              const SizedBox(height: 36),
            ]));
      });

  Future<void> _showAlbumEditorDialog(
    BuildContext context, {
    required AlbumProvider albumProvider,
    Album? album,
  }) {
    return showDialog<void>(
      context: context,
      builder: (context) => _AlbumEditorDialog(
        albumProvider: albumProvider,
        album: album,
      ),
    );
  }

  Future<void> _showDeleteAlbumDialog(
    BuildContext context, {
    required AlbumProvider albumProvider,
    required Album album,
  }) {
    return showDialog<void>(
      context: context,
      builder: (context) => _DeleteAlbumDialog(
        albumProvider: albumProvider,
        album: album,
      ),
    );
  }

  Future<void> _showAlbumMediaDialog(
    BuildContext context, {
    required Album album,
  }) {
    return showDialog<void>(
      context: context,
      builder: (context) => _AlbumMediaDialog(
        album: album,
        albumProvider: albumProvider,
        mediaProvider: mediaProvider,
        feedProvider: feedProvider,
      ),
    );
  }

  Future<void> _showAlbumSharesDialog(
    BuildContext context, {
    required Album album,
  }) {
    return showDialog<void>(
      context: context,
      builder: (context) => _AlbumSharesDialog(
        album: album,
        albumProvider: albumProvider,
        familyDirectoryProvider: familyDirectoryProvider,
        feedProvider: feedProvider,
        currentUserId: currentUserId,
      ),
    );
  }
}

class _AlbumCard extends StatefulWidget {
  const _AlbumCard(
      {required this.album,
      required this.albumProvider,
      required this.mediaProvider,
      required this.canManage,
      this.isSaving = false,
      this.isDeleting = false,
      this.onViewItems,
      this.onManageShares,
      this.onEdit,
      this.onDelete});
  final Album album;
  final AlbumProvider albumProvider;
  final MediaListProvider mediaProvider;
  final bool canManage;
  final bool isSaving;
  final bool isDeleting;
  final VoidCallback? onViewItems;
  final VoidCallback? onManageShares;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  @override
  State<_AlbumCard> createState() => _AlbumCardState();
}

class _AlbumCardState extends State<_AlbumCard> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_loadCover());
    });
  }

  Future<void> _loadCover() async {
    final cover = widget.album.coverMediaId;
    if (cover != null) {
      await widget.mediaProvider.ensureThumbnailById(cover);
      return;
    }
    await widget.albumProvider.loadAlbumMedia(widget.album.id);
    if (!mounted) return;
    final items = widget.albumProvider.mediaForAlbum(widget.album.id);
    if (items.isNotEmpty) {
      await widget.mediaProvider.ensureThumbnailLoaded(items.first);
    }
  }

  @override
  Widget build(BuildContext context) {
    final album = widget.album;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final media = widget.albumProvider.mediaForAlbum(album.id);
    final cover =
        album.coverMediaId ?? (media.isNotEmpty ? media.first.id : null);
    return VaultEnter(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Stack(children: [
        Padding(
            padding: const EdgeInsets.only(top: 7, right: 7),
            child: Container(
                height: 25,
                decoration: BoxDecoration(
                    color: colors.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(17)))),
        Padding(
            padding: const EdgeInsets.only(top: 3, left: 3, right: 3),
            child: Container(
                height: 25,
                decoration: BoxDecoration(
                    color: colors.outlineVariant,
                    borderRadius: BorderRadius.circular(17)))),
        Padding(
            padding: const EdgeInsets.only(top: 12),
            child: ClipRRect(
                borderRadius: BorderRadius.circular(17),
                child: AspectRatio(
                    aspectRatio: 1.13,
                    child: Stack(fit: StackFit.expand, children: [
                      if (cover != null)
                        VaultImage(
                            url: widget.mediaProvider.thumbnailUrlFor(cover),
                            label: album.name)
                      else
                        ColoredBox(
                            color: colors.surfaceContainerHighest,
                            child: Center(
                                child: Icon(Icons.photo_library_outlined,
                                    color: colors.onSurfaceVariant))),
                      Positioned.fill(
                          child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                  key: ValueKey<String>(
                                      'album-media-${album.id}'),
                                  onTap: widget.onViewItems,
                                  child: Semantics(
                                      label: 'Open ${album.name}',
                                      button: true,
                                      child: const SizedBox.expand())))),
                      Positioned(
                          left: 10,
                          bottom: 10,
                          child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 9, vertical: 6),
                              decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: .5),
                                  borderRadius: BorderRadius.circular(20)),
                              child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                        album.isOwnedByCurrentUser
                                            ? Icons.lock_outline_rounded
                                            : Icons.people_outline_rounded,
                                        color: Colors.white,
                                        size: 11),
                                    const SizedBox(width: 5),
                                    Text(
                                        album.isOwnedByCurrentUser
                                            ? 'Your collection'
                                            : 'Shared with you',
                                        style: const TextStyle(
                                            color: Colors.white, fontSize: 9))
                                  ]))),
                    ])))),
      ]),
      const SizedBox(height: 12),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(album.name,
              style: theme.textTheme.titleSmall,
              maxLines: 2,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 5),
          Text(
              '${album.mediaCount} ${album.mediaCount == 1 ? 'memory' : 'memories'}',
              style: TextStyle(fontSize: 10, color: colors.onSurfaceVariant))
        ])),
        if (widget.canManage)
          PopupMenuButton<String>(
              tooltip: 'Collection options',
              onSelected: (value) {
                if (value == 'edit') widget.onEdit?.call();
                if (value == 'delete') widget.onDelete?.call();
              },
              itemBuilder: (_) => [
                    PopupMenuItem(
                        key: ValueKey('edit-album-${album.id}'),
                        value: 'edit',
                        child: const Text('Edit collection')),
                    PopupMenuItem(
                        key: ValueKey('delete-album-${album.id}'),
                        value: 'delete',
                        child: const Text('Delete collection'))
                  ]),
      ]),
      if (widget.canManage)
        TextButton.icon(
            key: ValueKey<String>('album-share-${album.id}'),
            onPressed: widget.onManageShares,
            icon: const Icon(Icons.ios_share_rounded, size: 14),
            label: const Text('Choose who sees it',
                style: TextStyle(fontSize: 10))),
    ]));
  }
}

class _AlbumMediaDialog extends StatefulWidget {
  const _AlbumMediaDialog(
      {required this.album,
      required this.albumProvider,
      required this.mediaProvider,
      this.feedProvider});
  final Album album;
  final AlbumProvider albumProvider;
  final MediaListProvider mediaProvider;
  final FeedProvider? feedProvider;
  @override
  State<_AlbumMediaDialog> createState() => _AlbumMediaDialogState();
}

class _AlbumMediaDialogState extends State<_AlbumMediaDialog> {
  bool _adding = false;
  final Set<String> _selected = {};
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(widget.albumProvider.loadAlbumMedia(widget.album.id));
      }
    });
  }

  void _open(Media media) {
    if (widget.feedProvider == null) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => MediaViewer(
            media: media,
            provider: widget.feedProvider!,
            onChanged: () async {
              await widget.albumProvider.loadAlbumMedia(widget.album.id);
              await widget.mediaProvider.load();
            })));
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: Listenable.merge([widget.albumProvider, widget.mediaProvider]),
      builder: (context, _) {
        final theme = Theme.of(context);
        final existing = widget.albumProvider.mediaForAlbum(widget.album.id);
        final ids = existing.map((m) => m.id).toSet();
        final available = widget.mediaProvider.allItems
            .where((m) =>
                m.ownerId == widget.album.ownerId &&
                m.status == MediaStatus.ready &&
                !ids.contains(m.id))
            .toList();
        final canManage = widget.albumProvider.canManage(widget.album);
        final busy = widget.albumProvider.isMutatingAlbumMedia(widget.album.id);
        final items = _adding ? available : existing;
        return Dialog(
            insetPadding: const EdgeInsets.all(16),
            child: ConstrainedBox(
                constraints:
                    const BoxConstraints(maxWidth: 980, maxHeight: 800),
                child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Expanded(
                                child: Text(widget.album.name,
                                    style: theme.textTheme.headlineSmall)),
                            IconButton(
                                tooltip: 'Close collection',
                                onPressed: () => Navigator.pop(context),
                                icon: const Icon(Icons.close_rounded))
                          ]),
                          const SizedBox(height: 6),
                          Text(
                              'A collection of moments. Originals stay in your vault.',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: theme.colorScheme.onSurfaceVariant)),
                          const SizedBox(height: 20),
                          if (canManage)
                            Row(children: [
                              VaultPill('In this collection',
                                  selected: !_adding,
                                  onTap: () => setState(() => _adding = false)),
                              const SizedBox(width: 8),
                              Expanded(
                                  child: SingleChildScrollView(
                                      scrollDirection: Axis.horizontal,
                                      child: VaultPill('Add from vault',
                                          selected: _adding,
                                          onTap: () =>
                                              setState(() => _adding = true))))
                            ]),
                          if (widget.albumProvider.errorMessage != null)
                            Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: Text(widget.albumProvider.errorMessage!,
                                    style: TextStyle(
                                        color: theme.colorScheme.error))),
                          const SizedBox(height: 18),
                          Expanded(
                              child: items.isEmpty
                                  ? Center(
                                      child: Text(
                                          _adding
                                              ? 'Add a few memories to your vault first.'
                                              : 'This collection is waiting for its first memory.',
                                          textAlign: TextAlign.center))
                                  : SingleChildScrollView(
                                      child: MemoryMasonry(
                                          items: items,
                                          builder: (media, index) =>
                                              _CollectionPhoto(
                                                  media: media,
                                                  provider:
                                                      widget.mediaProvider,
                                                  selected: _adding &&
                                                      _selected
                                                          .contains(media.id),
                                                  selectable: _adding,
                                                  onTap: () {
                                                    if (_adding) {
                                                      setState(() {
                                                        if (!_selected
                                                            .add(media.id)) {
                                                          _selected
                                                              .remove(media.id);
                                                        }
                                                      });
                                                    } else {
                                                      _open(media);
                                                    }
                                                  },
                                                  onRemove: !_adding &&
                                                          canManage &&
                                                          !busy
                                                      ? () => widget
                                                          .albumProvider
                                                          .removeMediaFromAlbum(
                                                              albumId: widget
                                                                  .album.id,
                                                              mediaId: media.id)
                                                      : null)))),
                          if (_adding)
                            Padding(
                                padding: const EdgeInsets.only(top: 16),
                                child: SizedBox(
                                    width: double.infinity,
                                    child: FilledButton(
                                        key: ValueKey<String>(
                                            'album-media-add-${widget.album.id}'),
                                        onPressed: busy || _selected.isEmpty
                                            ? null
                                            : () async {
                                                final added = await widget
                                                    .albumProvider
                                                    .addMediaToAlbum(
                                                        albumId:
                                                            widget.album.id,
                                                        media: available
                                                            .where((m) =>
                                                                _selected
                                                                    .contains(
                                                                        m.id))
                                                            .toList());
                                                if (mounted && added) {
                                                  setState(() {
                                                    _selected.clear();
                                                    _adding = false;
                                                  });
                                                }
                                              },
                                        child: Text(busy
                                            ? 'Adding…'
                                            : 'Add ${_selected.length} ${_selected.length == 1 ? 'memory' : 'memories'}')))),
                        ]))));
      });
}

class _CollectionPhoto extends StatefulWidget {
  const _CollectionPhoto(
      {required this.media,
      required this.provider,
      required this.onTap,
      this.onRemove,
      this.selectable = false,
      this.selected = false});
  final Media media;
  final MediaListProvider provider;
  final VoidCallback onTap;
  final VoidCallback? onRemove;
  final bool selectable;
  final bool selected;
  @override
  State<_CollectionPhoto> createState() => _CollectionPhotoState();
}

class _CollectionPhotoState extends State<_CollectionPhoto> {
  @override
  void initState() {
    super.initState();
    unawaited(widget.provider.ensureThumbnailLoaded(widget.media));
  }

  @override
  Widget build(BuildContext context) => ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: AspectRatio(
          aspectRatio: widget.media.aspectRatio.clamp(.65, 1.5),
          child: Stack(fit: StackFit.expand, children: [
            VaultImage(
                url: widget.provider.thumbnailUrlFor(widget.media.id),
                label: widget.media.filename),
            Positioned.fill(
                child: Material(
                    color: widget.selected
                        ? Theme.of(context)
                            .colorScheme
                            .primary
                            .withValues(alpha: .2)
                        : Colors.transparent,
                    child: InkWell(
                        onTap: widget.onTap,
                        child: Semantics(
                            label: widget.media.filename,
                            button: true,
                            selected: widget.selected,
                            child: const SizedBox.expand())))),
            if (widget.selectable)
              Positioned(
                  right: 10,
                  top: 10,
                  child: IgnorePointer(
                      child: Icon(
                          widget.selected
                              ? Icons.check_circle_rounded
                              : Icons.radio_button_unchecked_rounded,
                          color: Colors.white,
                          size: 26))),
            if (widget.onRemove != null)
              Positioned(
                  right: 4,
                  top: 4,
                  child: IconButton(
                      tooltip: 'Remove from collection',
                      onPressed: widget.onRemove,
                      style: IconButton.styleFrom(
                          backgroundColor: Colors.black45,
                          foregroundColor: Colors.white),
                      icon: const Icon(Icons.remove_rounded, size: 18))),
          ])));
}

class _AlbumSharesDialog extends StatefulWidget {
  const _AlbumSharesDialog({
    required this.album,
    required this.albumProvider,
    required this.familyDirectoryProvider,
    required this.currentUserId,
    this.feedProvider,
  });

  final Album album;
  final AlbumProvider albumProvider;
  final FamilyDirectoryProvider familyDirectoryProvider;
  final String currentUserId;
  final FeedProvider? feedProvider;

  @override
  State<_AlbumSharesDialog> createState() => _AlbumSharesDialogState();
}

class _AlbumSharesDialogState extends State<_AlbumSharesDialog> {
  String? _selectedRecipientId;
  AlbumPermission _permission = AlbumPermission.view;
  DateTime? _expiresAt;

  String _recipientName(AlbumShare share) {
    if (!share.isFamilyShare) {
      return share.recipient?.displayName ?? 'Family member';
    }
    for (final family in widget.feedProvider?.families ?? []) {
      if (family.id == share.familyId) return 'Everyone in ${family.name}';
    }
    return 'Original family';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(widget.albumProvider.loadAlbumShares(widget.album.id));
      if (widget.feedProvider != null &&
          widget.feedProvider!.families.isEmpty) {
        unawaited(widget.feedProvider!.loadFamilies());
      }
      if (!widget.familyDirectoryProvider.hasLoaded &&
          !widget.familyDirectoryProvider.isLoading) {
        unawaited(widget.familyDirectoryProvider.load());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[
        widget.albumProvider,
        widget.familyDirectoryProvider,
        if (widget.feedProvider != null) widget.feedProvider!,
      ]),
      builder: (context, _) {
        final theme = Theme.of(context);
        final shares = widget.albumProvider.sharesForAlbum(widget.album.id);
        final candidates = widget.familyDirectoryProvider.users
            .where(
              (user) =>
                  user.id != widget.album.ownerId &&
                  user.id != widget.currentUserId,
            )
            .toList(growable: false);

        return Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 840, maxHeight: 640),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Share ${widget.album.name}',
                              style: theme.textTheme.headlineSmall,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Choose who can view or add to this album. Its contents stay with their owners.',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  if (widget.albumProvider.errorMessage != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      widget.albumProvider.errorMessage!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final useColumns = constraints.maxWidth >= 760;

                        final createCard = Card(
                          color: theme.colorScheme.surfaceContainerLowest,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: SingleChildScrollView(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Create a share',
                                    style: theme.textTheme.titleLarge,
                                  ),
                                  const SizedBox(height: 16),
                                  DropdownButtonFormField<String?>(
                                    key: ValueKey<String>(
                                      'album-share-recipient-${widget.album.id}',
                                    ),
                                    initialValue: _selectedRecipientId,
                                    isExpanded: true,
                                    decoration: const InputDecoration(
                                      labelText: 'Recipient',
                                    ),
                                    items: <DropdownMenuItem<String?>>[
                                      if (widget.feedProvider == null)
                                        DropdownMenuItem<String?>(
                                            value: null,
                                            child: _FamilyRecipientLabel(
                                                theme: theme)),
                                      ...?widget.feedProvider?.families.map(
                                          (family) => DropdownMenuItem<String?>(
                                              value: 'family:${family.id}',
                                              child: Text(
                                                  'Everyone in ${family.name}'))),
                                      ...candidates.map(
                                        (user) => DropdownMenuItem<String?>(
                                          value: user.id,
                                          child: _DirectoryRecipientLabel(
                                            user: user,
                                            directoryProvider:
                                                widget.familyDirectoryProvider,
                                          ),
                                        ),
                                      ),
                                    ],
                                    onChanged: (value) {
                                      setState(() {
                                        _selectedRecipientId = value;
                                      });
                                    },
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    widget.familyDirectoryProvider.isLoading &&
                                            !widget.familyDirectoryProvider
                                                .hasLoaded
                                        ? 'Finding your family members…'
                                        : 'Only the people you choose can access this album.',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  if (widget.familyDirectoryProvider
                                          .errorMessage !=
                                      null) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      widget.familyDirectoryProvider
                                          .errorMessage!,
                                      style:
                                          theme.textTheme.bodyMedium?.copyWith(
                                        color: theme.colorScheme.error,
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 12),
                                  DropdownButtonFormField<AlbumPermission>(
                                    initialValue: _permission,
                                    isExpanded: true,
                                    decoration: const InputDecoration(
                                      labelText: 'Permission',
                                    ),
                                    items: AlbumPermission.values
                                        .map(
                                          (permission) =>
                                              DropdownMenuItem<AlbumPermission>(
                                            value: permission,
                                            child: Text(permission.label),
                                          ),
                                        )
                                        .toList(growable: false),
                                    onChanged: (value) {
                                      if (value == null) {
                                        return;
                                      }
                                      setState(() {
                                        _permission = value;
                                      });
                                    },
                                  ),
                                  const SizedBox(height: 12),
                                  Wrap(
                                    spacing: 12,
                                    runSpacing: 12,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      OutlinedButton.icon(
                                        onPressed: () async {
                                          final selectedDate =
                                              await showDatePicker(
                                            context: context,
                                            firstDate: DateTime.now(),
                                            lastDate: DateTime.now().add(
                                              const Duration(days: 365),
                                            ),
                                            initialDate:
                                                _expiresAt ?? DateTime.now(),
                                          );
                                          if (!mounted ||
                                              selectedDate == null) {
                                            return;
                                          }
                                          setState(() {
                                            _expiresAt = DateTime.utc(
                                              selectedDate.year,
                                              selectedDate.month,
                                              selectedDate.day,
                                              23,
                                              59,
                                              59,
                                            );
                                          });
                                        },
                                        icon: const Icon(Icons.event_outlined),
                                        label: Text(
                                          _expiresAt == null
                                              ? 'No expiry'
                                              : 'Expires ${DateFormatter.mediumDate(_expiresAt!)}',
                                        ),
                                      ),
                                      if (_expiresAt != null)
                                        TextButton(
                                          onPressed: () {
                                            setState(() {
                                              _expiresAt = null;
                                            });
                                          },
                                          child: const Text('Clear expiry'),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  FilledButton.icon(
                                    key: ValueKey<String>(
                                      'album-share-submit-${widget.album.id}',
                                    ),
                                    onPressed: (widget.feedProvider != null &&
                                                _selectedRecipientId == null) ||
                                            widget.albumProvider
                                                .isMutatingAlbumShares(
                                                    widget.album.id)
                                        ? null
                                        : () async {
                                            final created = await widget
                                                .albumProvider
                                                .createShare(
                                              albumId: widget.album.id,
                                              permission: _permission,
                                              sharedWith: _selectedRecipientId
                                                          ?.startsWith(
                                                              'family:') ==
                                                      true
                                                  ? null
                                                  : _selectedRecipientId,
                                              familyId: _selectedRecipientId
                                                          ?.startsWith(
                                                              'family:') ==
                                                      true
                                                  ? _selectedRecipientId!
                                                      .substring(7)
                                                  : null,
                                              expiresAt: _expiresAt,
                                            );
                                            if (!mounted || !created) {
                                              return;
                                            }
                                            setState(() {
                                              _selectedRecipientId = null;
                                              _permission =
                                                  AlbumPermission.view;
                                              _expiresAt = null;
                                            });
                                          },
                                    icon: widget.albumProvider
                                            .isMutatingAlbumShares(
                                                widget.album.id)
                                        ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Icon(Icons.share_rounded),
                                    label: const Text('Create share'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );

                        final sharesCard = Card(
                          color: theme.colorScheme.surfaceContainerLowest,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Active shares',
                                  style: theme.textTheme.titleLarge,
                                ),
                                const SizedBox(height: 16),
                                if (widget.albumProvider.isLoadingAlbumShares(
                                        widget.album.id) &&
                                    shares.isEmpty)
                                  const Expanded(
                                    child: Center(
                                      child: CircularProgressIndicator(),
                                    ),
                                  )
                                else if (shares.isEmpty)
                                  Expanded(
                                    child: Center(
                                      child: Text(
                                        'No active shares yet.',
                                        style: theme.textTheme.bodyMedium,
                                      ),
                                    ),
                                  )
                                else
                                  Expanded(
                                    child: ListView.separated(
                                      itemCount: shares.length,
                                      separatorBuilder: (_, __) =>
                                          const Divider(height: 20),
                                      itemBuilder: (context, index) {
                                        final share = shares[index];
                                        return Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                if (share.recipient == null ||
                                                    share.isFamilyShare)
                                                  CircleAvatar(
                                                    radius: 16,
                                                    backgroundColor: theme
                                                        .colorScheme
                                                        .secondaryContainer,
                                                    child: Icon(
                                                      Icons.groups_rounded,
                                                      size: 18,
                                                      color: theme.colorScheme
                                                          .onSecondaryContainer,
                                                    ),
                                                  )
                                                else
                                                  UserAvatar(
                                                    userId: share.recipient!.id,
                                                    displayName: share
                                                        .recipient!.displayName,
                                                    initialAvatarUrl: share
                                                        .recipient!.avatarUrl,
                                                    directoryProvider: widget
                                                        .familyDirectoryProvider,
                                                    radius: 16,
                                                  ),
                                                const SizedBox(width: 12),
                                                Expanded(
                                                  child: Text(
                                                    _recipientName(share),
                                                    style: theme
                                                        .textTheme.titleMedium,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              share.permission.label,
                                              style: theme.textTheme.bodyMedium
                                                  ?.copyWith(
                                                color: theme.colorScheme
                                                    .onSurfaceVariant,
                                              ),
                                            ),
                                            if (share.expiresAt != null) ...[
                                              const SizedBox(height: 4),
                                              Text(
                                                'Expires ${DateFormatter.mediumDate(share.expiresAt!)}',
                                                style: theme
                                                    .textTheme.bodyMedium
                                                    ?.copyWith(
                                                  color: theme.colorScheme
                                                      .onSurfaceVariant,
                                                ),
                                              ),
                                            ],
                                            const SizedBox(height: 8),
                                            TextButton.icon(
                                              onPressed: widget.albumProvider
                                                      .isMutatingAlbumShares(
                                                          widget.album.id)
                                                  ? null
                                                  : () {
                                                      widget.albumProvider
                                                          .revokeShare(
                                                        albumId:
                                                            widget.album.id,
                                                        shareId: share.id,
                                                      );
                                                    },
                                              icon: const Icon(
                                                Icons.link_off_rounded,
                                              ),
                                              label: const Text('Revoke'),
                                            ),
                                          ],
                                        );
                                      },
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );

                        if (useColumns) {
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: createCard),
                              const SizedBox(width: 20),
                              Expanded(child: sharesCard),
                            ],
                          );
                        }

                        return Column(
                          children: [
                            Expanded(child: createCard),
                            const SizedBox(height: 20),
                            Expanded(child: sharesCard),
                          ],
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Close'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _DirectoryRecipientLabel extends StatelessWidget {
  const _DirectoryRecipientLabel({
    required this.user,
    required this.directoryProvider,
  });

  final DirectoryUser user;
  final FamilyDirectoryProvider directoryProvider;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        UserAvatar(
          userId: user.id,
          displayName: user.displayName,
          initialAvatarUrl: user.avatarUrl,
          directoryProvider: directoryProvider,
          radius: 14,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            user.displayName,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _FamilyRecipientLabel extends StatelessWidget {
  const _FamilyRecipientLabel({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CircleAvatar(
          radius: 14,
          backgroundColor: theme.colorScheme.secondaryContainer,
          child: Icon(
            Icons.groups_rounded,
            size: 16,
            color: theme.colorScheme.onSecondaryContainer,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'Original family',
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _AlbumEditorDialog extends StatefulWidget {
  const _AlbumEditorDialog({
    required this.albumProvider,
    this.album,
  });

  final AlbumProvider albumProvider;
  final Album? album;

  @override
  State<_AlbumEditorDialog> createState() => _AlbumEditorDialogState();
}

class _AlbumEditorDialogState extends State<_AlbumEditorDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;

  bool get _isEditing => widget.album != null;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.album?.name ?? '')
      ..addListener(_handleChanged);
    _descriptionController = TextEditingController(
      text: widget.album?.description ?? '',
    )..addListener(_handleChanged);
  }

  @override
  void dispose() {
    _nameController
      ..removeListener(_handleChanged)
      ..dispose();
    _descriptionController
      ..removeListener(_handleChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AnimatedBuilder(
      animation: widget.albumProvider,
      builder: (context, _) {
        final album = widget.album;
        final isBusy = _isEditing && album != null
            ? widget.albumProvider.isSavingAlbum(album.id)
            : widget.albumProvider.isCreating;

        return AlertDialog(
          title: Text(_isEditing ? 'Edit collection' : 'Create album'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  key: const ValueKey<String>('album-name-field'),
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Collection name',
                    hintText: 'Weekend in the mountains',
                  ),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const ValueKey<String>('album-description-field'),
                  controller: _descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    hintText: 'Optional context for the album',
                  ),
                  maxLines: 4,
                  minLines: 3,
                ),
                if (widget.albumProvider.errorMessage != null) ...[
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      widget.albumProvider.errorMessage!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isBusy ? null : () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const ValueKey<String>('album-save-button'),
              onPressed: isBusy ? null : _save,
              child: Text(
                isBusy
                    ? (_isEditing ? 'Saving...' : 'Creating...')
                    : (_isEditing ? 'Save changes' : 'Create album'),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _save() async {
    final didSave = _isEditing
        ? await widget.albumProvider.updateAlbum(
            albumId: widget.album!.id,
            name: _nameController.text,
            description: _descriptionController.text,
          )
        : await widget.albumProvider.createAlbum(
            name: _nameController.text,
            description: _descriptionController.text,
          );

    if (!mounted || !didSave) {
      return;
    }

    Navigator.of(context).pop();
  }

  void _handleChanged() {
    if (mounted) {
      setState(() {});
    }
  }
}

class _DeleteAlbumDialog extends StatelessWidget {
  const _DeleteAlbumDialog({
    required this.albumProvider,
    required this.album,
  });

  final AlbumProvider albumProvider;
  final Album album;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: albumProvider,
      builder: (context, _) {
        final isDeleting = albumProvider.isDeletingAlbum(album.id);

        return AlertDialog(
          title: const Text('Delete collection'),
          content: Text(
            'Delete "${album.name}"? The collection will disappear. Your originals will stay in your vault.',
          ),
          actions: [
            TextButton(
              onPressed: isDeleting ? null : () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: isDeleting
                  ? null
                  : () async {
                      final deleted = await albumProvider.deleteAlbum(album.id);
                      if (!context.mounted || !deleted) {
                        return;
                      }
                      Navigator.of(context).pop();
                    },
              child: Text(isDeleting ? 'Deleting...' : 'Delete collection'),
            ),
          ],
        );
      },
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
