import 'package:flutter/material.dart';
import '../../../core/network/api_exception.dart';
import '../../../shared/utils/date_formatter.dart';
import '../data/media_repository.dart';
import '../domain/media.dart';

class TrashScreen extends StatefulWidget {
  const TrashScreen({super.key, required this.repository});
  final MediaRepository repository;
  @override
  State<TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends State<TrashScreen> {
  List<Media> _items = [];
  String _cursor = '';
  String? _error;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool more = false}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final page = await widget.repository.trash(cursor: more ? _cursor : '');
      if (mounted) {
        setState(() {
          _items = more ? [..._items, ...page.items] : page.items;
          _cursor = page.nextCursor;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Unable to load Recently Deleted. Please try again.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<bool> _confirm(String title) async =>
      await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
                  title: Text(title),
                  content: const Text(
                      'This permanently removes the original and its previews. It cannot be undone in Mynube.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel')),
                    FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Permanently delete'))
                  ])) ??
      false;
  Future<void> _act(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      await _load();
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Unable to complete this action. Please try again.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Recently Deleted'), actions: [
          IconButton(
              tooltip: 'Refresh',
              onPressed: _busy ? null : _load,
              icon: const Icon(Icons.refresh_rounded)),
          IconButton(
              tooltip: 'Empty Recently Deleted',
              onPressed: _busy || _items.isEmpty
                  ? null
                  : () async {
                      if (await _confirm('Permanently delete all items?')) {
                        await _act(widget.repository.emptyTrash);
                      }
                    },
              icon: const Icon(Icons.delete_forever_outlined)),
        ]),
        body: Column(children: [
          const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                  'Items stay here for 30 days and continue to use storage. Restore an item to return it to your library. Permanent deletion finishes in the background.')),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null)
            Padding(
                padding: const EdgeInsets.all(16),
                child: Text(_error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error))),
          Expanded(
              child: _items.isEmpty && !_busy
                  ? const Center(
                      child: Text(
                          'Nothing here. Your memories are in your library.'))
                  : ListView.builder(
                      itemCount: _items.length + (_cursor.isNotEmpty ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index == _items.length) {
                          return TextButton(
                              onPressed: _busy ? null : () => _load(more: true),
                              child: const Text('More deleted items'));
                        }
                        final item = _items[index];
                        return ListTile(
                            title: Text(item.filename),
                            subtitle: item.purgesAt == null
                                ? null
                                : Text(
                                    'Deletes ${DateFormatter.mediumDate(item.purgesAt!.toLocal())}'),
                            trailing: Wrap(children: [
                              IconButton(
                                  tooltip: 'Restore to library',
                                  onPressed: _busy
                                      ? null
                                      : () => _act(() =>
                                          widget.repository.restore(item.id)),
                                  icon: const Icon(Icons.restore_rounded)),
                              IconButton(
                                  tooltip: 'Permanently delete',
                                  onPressed: _busy
                                      ? null
                                      : () async {
                                          if (await _confirm(
                                              'Permanently delete this item?')) {
                                            await _act(() => widget.repository
                                                .deletePermanently(item.id));
                                          }
                                        },
                                  icon: const Icon(
                                      Icons.delete_forever_outlined)),
                            ]));
                      })),
        ]),
      );
}
