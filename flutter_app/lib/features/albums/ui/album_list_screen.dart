import 'dart:async';

import 'package:flutter/material.dart';

import '../../../shared/widgets/user_avatar.dart';
import '../../../shared/utils/date_formatter.dart';
import '../../../shared/utils/file_size_formatter.dart';
import '../../directory/domain/directory_user.dart';
import '../../directory/providers/family_directory_provider.dart';
import '../../media/domain/media.dart';
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
  });

  final AlbumProvider albumProvider;
  final MediaListProvider mediaProvider;
  final FamilyDirectoryProvider familyDirectoryProvider;
  final String currentUserId;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[
        albumProvider,
        mediaProvider,
        familyDirectoryProvider,
      ]),
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
                        'Live album workspace',
                        style: theme.textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Owned and shared album collections now come from GET /albums, while album membership and sharing dialogs call the live /albums/:id/media and /albums/:id/shares endpoints.',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          OutlinedButton.icon(
                            onPressed: albumProvider.isLoading
                                ? null
                                : () {
                                    albumProvider.load();
                                  },
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('Refresh'),
                          ),
                          FilledButton.icon(
                            key: const ValueKey<String>('create-album-button'),
                            onPressed: albumProvider.isCreating
                                ? null
                                : () {
                                    _showAlbumEditorDialog(
                                      context,
                                      albumProvider: albumProvider,
                                    );
                                  },
                            icon: albumProvider.isCreating
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.add_rounded),
                            label: Text(
                              albumProvider.isCreating
                                  ? 'Creating...'
                                  : 'New album',
                            ),
                          ),
                        ],
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
                  ...ownedAlbums.map(
                    (album) => _AlbumCard(
                      album: album,
                      canManage: albumProvider.canManage(album),
                      isSaving: albumProvider.isSavingAlbum(album.id),
                      isDeleting: albumProvider.isDeletingAlbum(album.id),
                      onViewItems: () {
                        _showAlbumMediaDialog(
                          context,
                          album: album,
                        );
                      },
                      onManageShares: () {
                        _showAlbumSharesDialog(
                          context,
                          album: album,
                        );
                      },
                      onEdit: () {
                        _showAlbumEditorDialog(
                          context,
                          albumProvider: albumProvider,
                          album: album,
                        );
                      },
                      onDelete: () {
                        _showDeleteAlbumDialog(
                          context,
                          albumProvider: albumProvider,
                          album: album,
                        );
                      },
                    ),
                  ),
                const SizedBox(height: 20),
                Text('Shared with you', style: theme.textTheme.headlineSmall),
                const SizedBox(height: 12),
                if (sharedAlbums.isEmpty)
                  const _AlbumEmptyState(message: 'No shared albums yet.')
                else
                  ...sharedAlbums.map(
                    (album) => _AlbumCard(
                      album: album,
                      canManage: albumProvider.canManage(album),
                      onViewItems: () {
                        _showAlbumMediaDialog(
                          context,
                          album: album,
                        );
                      },
                      onManageShares: albumProvider.canManage(album)
                          ? () {
                              _showAlbumSharesDialog(
                                context,
                                album: album,
                              );
                            }
                          : null,
                    ),
                  ),
              ],
            ],
          ),
        );
      },
    );
  }

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
        currentUserId: currentUserId,
      ),
    );
  }
}

class _AlbumCard extends StatelessWidget {
  const _AlbumCard({
    required this.album,
    required this.canManage,
    this.isSaving = false,
    this.isDeleting = false,
    this.onViewItems,
    this.onManageShares,
    this.onEdit,
    this.onDelete,
  });

  final Album album;
  final bool canManage;
  final bool isSaving;
  final bool isDeleting;
  final VoidCallback? onViewItems;
  final VoidCallback? onManageShares;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

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
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(album.name, style: theme.textTheme.titleLarge),
                  Chip(
                    label: Text(
                      album.isOwnedByCurrentUser ? 'owned' : 'shared',
                    ),
                  ),
                  OutlinedButton.icon(
                    key: ValueKey<String>('album-media-${album.id}'),
                    onPressed: onViewItems,
                    icon: const Icon(Icons.photo_library_outlined),
                    label: Text(canManage ? 'Manage items' : 'View items'),
                  ),
                  if (canManage)
                    OutlinedButton.icon(
                      key: ValueKey<String>('album-share-${album.id}'),
                      onPressed: onManageShares,
                      icon: const Icon(Icons.share_outlined),
                      label: const Text('Share'),
                    ),
                  if (canManage)
                    OutlinedButton.icon(
                      key: ValueKey<String>('edit-album-${album.id}'),
                      onPressed: isSaving || isDeleting ? null : onEdit,
                      icon: isSaving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.edit_rounded),
                      label: const Text('Edit'),
                    ),
                  if (canManage)
                    TextButton.icon(
                      key: ValueKey<String>('delete-album-${album.id}'),
                      onPressed: isSaving || isDeleting ? null : onDelete,
                      icon: isDeleting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.delete_outline_rounded),
                      label: const Text('Delete'),
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

class _AlbumMediaDialog extends StatefulWidget {
  const _AlbumMediaDialog({
    required this.album,
    required this.albumProvider,
    required this.mediaProvider,
  });

  final Album album;
  final AlbumProvider albumProvider;
  final MediaListProvider mediaProvider;

  @override
  State<_AlbumMediaDialog> createState() => _AlbumMediaDialogState();
}

class _AlbumMediaDialogState extends State<_AlbumMediaDialog> {
  final Set<String> _selectedMediaIds = <String>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(widget.albumProvider.loadAlbumMedia(widget.album.id));
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[
        widget.albumProvider,
        widget.mediaProvider,
      ]),
      builder: (context, _) {
        final theme = Theme.of(context);
        final albumMedia = widget.albumProvider.mediaForAlbum(widget.album.id);
        final currentIds = albumMedia.map((item) => item.id).toSet();
        final availableItems = widget.mediaProvider.allItems
            .where((media) =>
                media.ownerId == widget.album.ownerId &&
                !currentIds.contains(media.id))
            .toList(growable: false)
          ..sort((left, right) => right.uploadedAt.compareTo(left.uploadedAt));
        final canManage = widget.albumProvider.canManage(widget.album);

        return Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980, maxHeight: 680),
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
                              '${widget.album.name} items',
                              style: theme.textTheme.headlineSmall,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Current API endpoint: GET/POST/DELETE /albums/${widget.album.id}/media',
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

                        if (!canManage) {
                          return _AlbumMediaPane(
                            title: 'Album contents',
                            isLoading: widget.albumProvider
                                .isLoadingAlbumMedia(widget.album.id),
                            isMutating: false,
                            items: albumMedia,
                            emptyMessage: 'No visible album items yet.',
                          );
                        }

                        final currentPane = _AlbumMediaPane(
                          title: 'In this album',
                          isLoading: widget.albumProvider
                              .isLoadingAlbumMedia(widget.album.id),
                          isMutating: widget.albumProvider
                              .isMutatingAlbumMedia(widget.album.id),
                          items: albumMedia,
                          emptyMessage: 'No items in this album yet.',
                          onRemove: (media) async {
                            await widget.albumProvider.removeMediaFromAlbum(
                              albumId: widget.album.id,
                              mediaId: media.id,
                            );
                          },
                          showRemove: true,
                        );
                        final availablePane = _AvailableMediaPane(
                          items: availableItems,
                          selectedMediaIds: _selectedMediaIds,
                          onSelectionChanged: (mediaId, selected) {
                            setState(() {
                              if (selected) {
                                _selectedMediaIds.add(mediaId);
                              } else {
                                _selectedMediaIds.remove(mediaId);
                              }
                            });
                          },
                        );

                        if (useColumns) {
                          return Row(
                            children: [
                              Expanded(child: currentPane),
                              const SizedBox(width: 20),
                              Expanded(child: availablePane),
                            ],
                          );
                        }

                        return Column(
                          children: [
                            Expanded(child: currentPane),
                            const SizedBox(height: 20),
                            Expanded(child: availablePane),
                          ],
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Close'),
                      ),
                      const Spacer(),
                      if (canManage)
                        FilledButton.icon(
                          key: ValueKey<String>(
                              'album-media-add-${widget.album.id}'),
                          onPressed: _selectedMediaIds.isEmpty ||
                                  widget.albumProvider
                                      .isMutatingAlbumMedia(widget.album.id)
                              ? null
                              : () async {
                                  final selectedItems = availableItems
                                      .where(
                                        (item) =>
                                            _selectedMediaIds.contains(item.id),
                                      )
                                      .toList(growable: false);
                                  final added = await widget.albumProvider
                                      .addMediaToAlbum(
                                    albumId: widget.album.id,
                                    media: selectedItems,
                                  );
                                  if (!mounted || !added) {
                                    return;
                                  }
                                  setState(() {
                                    _selectedMediaIds.clear();
                                  });
                                },
                          icon: widget.albumProvider
                                  .isMutatingAlbumMedia(widget.album.id)
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.playlist_add_rounded),
                          label: const Text('Add selected'),
                        ),
                    ],
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

class _AlbumSharesDialog extends StatefulWidget {
  const _AlbumSharesDialog({
    required this.album,
    required this.albumProvider,
    required this.familyDirectoryProvider,
    required this.currentUserId,
  });

  final Album album;
  final AlbumProvider albumProvider;
  final FamilyDirectoryProvider familyDirectoryProvider;
  final String currentUserId;

  @override
  State<_AlbumSharesDialog> createState() => _AlbumSharesDialogState();
}

class _AlbumSharesDialogState extends State<_AlbumSharesDialog> {
  String? _selectedRecipientId;
  AlbumPermission _permission = AlbumPermission.view;
  DateTime? _expiresAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(widget.albumProvider.loadAlbumShares(widget.album.id));
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
                              'Current API endpoint: GET/POST/DELETE /albums/${widget.album.id}/shares',
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
                                      DropdownMenuItem<String?>(
                                        value: null,
                                        child:
                                            _FamilyRecipientLabel(theme: theme),
                                      ),
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
                                        ? 'Loading family recipients from GET /users/directory...'
                                        : 'Recipient options come from GET /users/directory, and avatars refresh through GET /users/:id/avatar when a signed URL expires.',
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
                                    onPressed: widget.albumProvider
                                            .isMutatingAlbumShares(
                                                widget.album.id)
                                        ? null
                                        : () async {
                                            final created = await widget
                                                .albumProvider
                                                .createShare(
                                              albumId: widget.album.id,
                                              permission: _permission,
                                              sharedWith: _selectedRecipientId,
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
                                                    share.recipient
                                                            ?.displayName ??
                                                        share.sharedWith,
                                                    style: theme
                                                        .textTheme.titleMedium,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              '${share.permission.label} permission',
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
        const Expanded(
          child: Text(
            'Entire family',
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _AlbumMediaPane extends StatelessWidget {
  const _AlbumMediaPane({
    required this.title,
    required this.items,
    required this.emptyMessage,
    required this.isLoading,
    required this.isMutating,
    this.onRemove,
    this.showRemove = false,
  });

  final String title;
  final List<Media> items;
  final String emptyMessage;
  final bool isLoading;
  final bool isMutating;
  final bool showRemove;
  final ValueChanged<Media>? onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      color: theme.colorScheme.surfaceContainerLowest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleLarge),
            const SizedBox(height: 16),
            if (isLoading && items.isEmpty)
              const Expanded(
                child: Center(
                  child: CircularProgressIndicator(),
                ),
              )
            else if (items.isEmpty)
              Expanded(
                child: Center(
                  child: Text(
                    emptyMessage,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Divider(height: 20),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.filename,
                                style: theme.textTheme.titleMedium,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${item.mimeType} · ${FileSizeFormatter.compact(item.sizeBytes)}',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Uploaded ${DateFormatter.mediumDate(item.uploadedAt)}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (showRemove)
                          IconButton(
                            onPressed:
                                isMutating ? null : () => onRemove?.call(item),
                            icon: isMutating
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.remove_circle_outline),
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
  }
}

class _AvailableMediaPane extends StatelessWidget {
  const _AvailableMediaPane({
    required this.items,
    required this.selectedMediaIds,
    required this.onSelectionChanged,
  });

  final List<Media> items;
  final Set<String> selectedMediaIds;
  final void Function(String mediaId, bool selected) onSelectionChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      color: theme.colorScheme.surfaceContainerLowest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Add from library', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Only items owned by the album owner can be added.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            if (items.isEmpty)
              Expanded(
                child: Center(
                  child: Text(
                    'No additional owned media is available right now.',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Divider(height: 20),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final selected = selectedMediaIds.contains(item.id);
                    return CheckboxListTile(
                      value: selected,
                      onChanged: (value) {
                        onSelectionChanged(item.id, value ?? false);
                      },
                      contentPadding: EdgeInsets.zero,
                      title: Text(item.filename),
                      subtitle: Text(
                        '${item.mimeType} · ${FileSizeFormatter.compact(item.sizeBytes)}',
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
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
          title: Text(_isEditing ? 'Edit album' : 'Create album'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  key: const ValueKey<String>('album-name-field'),
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Album name',
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
          title: const Text('Delete album'),
          content: Text(
            'Delete "${album.name}"? The album will disappear, but the media inside it will stay in the library.',
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
              child: Text(isDeleting ? 'Deleting...' : 'Delete album'),
            ),
          ],
        );
      },
    );
  }
}

class _AlbumMeta extends StatelessWidget {
  const _AlbumMeta({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Text(
      label,
      style: theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
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
