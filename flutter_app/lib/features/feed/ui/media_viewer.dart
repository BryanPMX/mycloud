import 'package:flutter/material.dart';
import '../../../shared/widgets/vault_ui.dart';
import '../../../shared/utils/date_formatter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import '../../media/domain/media.dart';
import '../providers/feed_provider.dart';

class MediaViewer extends StatefulWidget {
  const MediaViewer(
      {super.key, required this.media, required this.provider, this.onChanged});
  final Future<void> Function()? onChanged;
  final Media media;
  final FeedProvider provider;
  @override
  State<MediaViewer> createState() => _MediaViewerState();
}

class _MediaViewerState extends State<MediaViewer> with WidgetsBindingObserver {
  String? _url;
  String? _error;
  VideoPlayerController? _video;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  Future<void> _load() async {
    final old = _video;
    _video = null;
    await old?.dispose();
    if (!mounted) return;
    setState(() {
      _url = null;
      _error = null;
    });
    try {
      final url = await (widget.media.mimeType == "image/heic"
          ? widget.provider.preview(widget.media.id, size: "large")
          : widget.provider.original(widget.media.id));
      if (!mounted) return;
      if (widget.media.isVideo && !url.startsWith('asset:')) {
        final video = VideoPlayerController.networkUrl(Uri.parse(url));
        _video = video;
        await video.initialize();
        if (!mounted) return;
      }
      setState(() {
        _url = url;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Unable to open this original. Try again or download it.';
        });
      }
    }
  }

  Future<void> _trash() async {
    final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('Move to Recently Deleted?'),
                content: const Text(
                    'This removes the item from shared feeds and albums. You can restore it from Recently Deleted for 30 days. It continues to use storage until permanently deleted.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Move to Recently Deleted'))
                ]));
    if (confirm != true) return;
    try {
      await widget.provider.mediaRepository.moveToTrash(widget.media.id);
      await widget.onChanged?.call();
      if (mounted) {
        Navigator.pop(context);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Unable to delete this item. Please try again.')));
      }
    }
  }

  Future<void> _share() async {
    await widget.provider.loadFamilies();
    if (!mounted) return;
    if (widget.provider.families.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Create or join a family in the Shared tab first.')));
      return;
    }
    String family = widget.provider.selected!.id;
    final caption = TextEditingController();
    bool busy = false;
    String? error;
    await showDialog<void>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
            builder: (context, setState) => AlertDialog(
                    title: const Text('Share a moment'),
                    content: Column(mainAxisSize: MainAxisSize.min, children: [
                      DropdownButtonFormField<String>(
                          initialValue: family,
                          decoration:
                              const InputDecoration(labelText: 'Family'),
                          items: widget.provider.families
                              .map((f) => DropdownMenuItem(
                                  value: f.id, child: Text(f.name)))
                              .toList(),
                          onChanged: busy
                              ? null
                              : (value) {
                                  if (value != null) {
                                    setState(() {
                                      family = value;
                                    });
                                  }
                                }),
                      TextField(
                          controller: caption,
                          maxLength: 2000,
                          maxLines: 2,
                          decoration: const InputDecoration(
                              labelText: 'Caption (optional)')),
                      const Text(
                          'Your original stays in your vault. Only this family can see the post.'),
                      if (error != null) Text(error!),
                    ]),
                    actions: [
                      TextButton(
                          onPressed:
                              busy ? null : () => Navigator.pop(dialogContext),
                          child: const Text('Cancel')),
                      FilledButton(
                          onPressed: busy
                              ? null
                              : () async {
                                  setState(() {
                                    busy = true;
                                    error = null;
                                  });
                                  try {
                                    await widget.provider.publish(
                                        caption.text, [widget.media.id],
                                        familyID: family);
                                    if (dialogContext.mounted) {
                                      Navigator.pop(dialogContext);
                                    }
                                  } catch (_) {
                                    if (dialogContext.mounted) {
                                      setState(() {
                                        busy = false;
                                        error =
                                            'Unable to share. Please try again.';
                                      });
                                    }
                                  }
                                },
                          child: Text(busy ? 'Sharing…' : 'Share'))
                    ])));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      caption.dispose();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _video?.pause();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _video?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            leading: IconButton(
                tooltip: 'Close memory',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded)),
            title:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                  DateFormatter.mediumDate(
                      widget.media.takenAt ?? widget.media.uploadedAt),
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700)),
              const SizedBox(height: 3),
              Text(
                  widget.media.ownerId == widget.provider.auth.currentUser?.id
                      ? 'From your vault'
                      : 'Shared with you',
                  style: const TextStyle(fontSize: 10, color: Colors.white60))
            ]),
            actions: [
              if (widget.media.ownerId ==
                  widget.provider.auth.currentUser?.id) ...[
                IconButton(
                    tooltip: 'Share with family',
                    onPressed: _share,
                    icon: const Icon(Icons.ios_share_rounded)),
                IconButton(
                    tooltip: 'Move to Recently Deleted',
                    onPressed: _trash,
                    icon: const Icon(Icons.delete_outline_rounded)),
              ],
              IconButton(
                  tooltip: 'Download original',
                  icon: const Icon(Icons.download_rounded),
                  onPressed: () async {
                    try {
                      final url =
                          await widget.provider.original(widget.media.id);
                      if (!mounted) return;
                      final launched = await launchUrl(Uri.parse(url),
                          mode: LaunchMode.externalApplication);
                      if (!launched && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Unable to open the download.')));
                      }
                    } catch (_) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text(
                                    'Unable to download. Please try again.')));
                      }
                    }
                  }),
            ]),
        body: Center(
            child: _error != null
                ? Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(_error!, style: const TextStyle(color: Colors.white)),
                    TextButton(onPressed: _load, child: const Text('Try again'))
                  ])
                : _url == null
                    ? const CircularProgressIndicator()
                    : _video != null
                        ? ValueListenableBuilder<VideoPlayerValue>(
                            valueListenable: _video!,
                            builder: (context, value, _) => Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Flexible(
                                          child: AspectRatio(
                                              aspectRatio: value.aspectRatio,
                                              child: VideoPlayer(_video!))),
                                      Padding(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 18, vertical: 12),
                                          child: Row(children: [
                                            IconButton(
                                                tooltip: value.isPlaying
                                                    ? 'Pause video'
                                                    : 'Play video',
                                                color: Colors.white,
                                                icon: Icon(value.isPlaying
                                                    ? Icons.pause_rounded
                                                    : Icons.play_arrow_rounded),
                                                onPressed: () => value.isPlaying
                                                    ? _video!.pause()
                                                    : _video!.play()),
                                            Text(
                                                '${value.position.inMinutes}:${(value.position.inSeconds % 60).toString().padLeft(2, '0')}',
                                                style: const TextStyle(
                                                    color: Colors.white70,
                                                    fontSize: 11)),
                                            Expanded(
                                                child: Slider(
                                                    value: value
                                                        .position.inMilliseconds
                                                        .toDouble()
                                                        .clamp(
                                                            0,
                                                            value.duration
                                                                .inMilliseconds
                                                                .toDouble()),
                                                    max: value.duration.inMilliseconds > 0
                                                        ? value.duration
                                                            .inMilliseconds
                                                            .toDouble()
                                                        : 1,
                                                    onChanged: (position) =>
                                                        _video!.seekTo(Duration(
                                                            milliseconds:
                                                                position.toInt())),
                                                    activeColor: Colors.white,
                                                    inactiveColor: Colors.white24,
                                                    semanticFormatterCallback: (v) => '${(v / 1000).round()} seconds')),
                                            Text(
                                                '${value.duration.inMinutes}:${(value.duration.inSeconds % 60).toString().padLeft(2, '0')}',
                                                style: const TextStyle(
                                                    color: Colors.white70,
                                                    fontSize: 11)),
                                          ])),
                                      if (value.hasError)
                                        TextButton(
                                            onPressed: _load,
                                            child: const Text('Reload video')),
                                    ]))
                        : InteractiveViewer(
                            minScale: 0.5,
                            maxScale: 6,
                            child: VaultImage(
                                url: _url!,
                                fit: BoxFit.contain,
                                label: widget.media.filename))),
      );
}
