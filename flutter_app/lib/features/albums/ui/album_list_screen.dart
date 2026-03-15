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
                        'Owned and shared album collections now come from GET /albums, and owned albums can now be created, renamed, described, and deleted from the Flutter client.',
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
                      canManage: true,
                      isSaving: albumProvider.isSavingAlbum(album.id),
                      isDeleting: albumProvider.isDeletingAlbum(album.id),
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
                  ...sharedAlbums.map((album) => _AlbumCard(album: album)),
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
}

class _AlbumCard extends StatelessWidget {
  const _AlbumCard({
    required this.album,
    this.canManage = false,
    this.isSaving = false,
    this.isDeleting = false,
    this.onEdit,
    this.onDelete,
  });

  final Album album;
  final bool canManage;
  final bool isSaving;
  final bool isDeleting;
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
        final isBusy = _isEditing
            ? widget.albumProvider.isSavingAlbum(widget.album!.id)
            : widget.albumProvider.isCreating;

        return AlertDialog(
          title: Text(_isEditing ? 'Edit album' : 'Create album'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  key: const ValueKey<String>('album-name-field'),
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Album name',
                    hintText: 'Summer road trip',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const ValueKey<String>('album-description-field'),
                  controller: _descriptionController,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    hintText: 'What belongs in this album?',
                  ),
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
              onPressed: isBusy || _nameController.text.trim().isEmpty
                  ? null
                  : _submit,
              child: Text(
                isBusy
                    ? (_isEditing ? 'Saving...' : 'Creating...')
                    : (_isEditing ? 'Save' : 'Create'),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _submit() async {
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
    if (didSave && mounted) {
      Navigator.of(context).pop();
    }
  }

  void _handleChanged() {
    setState(() {});
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
          title: const Text('Delete album?'),
          content: Text(
            'Remove "${album.name}" from your owned albums. This deletes the album record but does not delete the media itself.',
          ),
          actions: [
            TextButton(
              onPressed: isDeleting ? null : () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton.tonal(
              onPressed: isDeleting
                  ? null
                  : () async {
                      final didDelete = await albumProvider.deleteAlbum(
                        album.id,
                      );
                      if (didDelete && context.mounted) {
                        Navigator.of(context).pop();
                      }
                    },
              child: Text(isDeleting ? 'Deleting...' : 'Delete'),
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
