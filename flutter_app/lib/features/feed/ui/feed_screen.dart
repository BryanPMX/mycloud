import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/network/api_exception.dart';
import '../../../shared/utils/date_formatter.dart';
import '../../media/domain/media.dart';
import '../../media/providers/media_list_provider.dart';
import '../domain/family.dart';
import '../providers/feed_provider.dart';
import 'media_viewer.dart';
import '../../../shared/widgets/vault_ui.dart';

class FeedScreen extends StatefulWidget {
  const FeedScreen(
      {super.key, required this.provider, required this.mediaProvider});
  final FeedProvider provider;
  final MediaListProvider mediaProvider;
  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  FeedProvider get feed => widget.provider;
  @override
  void initState() {
    super.initState();
    if (feed.families.isEmpty) unawaited(feed.loadFamilies());
  }

  void _message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } on ApiException catch (e) {
      _message(e.message);
    } catch (_) {
      _message('Unable to complete that action. Please try again.');
    }
  }

  Future<String?> _ask(String title, String label,
      {String? help, int maxLength = 100}) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
                title: Text(title),
                content: Column(mainAxisSize: MainAxisSize.min, children: [
                  if (help != null) ...[Text(help), const SizedBox(height: 16)],
                  TextField(
                      controller: controller,
                      autofocus: true,
                      maxLength: maxLength,
                      decoration: InputDecoration(labelText: label)),
                ]),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () {
                        if (controller.text.trim().isNotEmpty) {
                          Navigator.pop(context, controller.text.trim());
                        }
                      },
                      child: const Text('Continue'))
                ]));
    // The dialog's exit animation can still reference the controller this frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
    return result;
  }

  Future<void> _newFamily() async {
    final name = await _ask('Create a circle', 'Circle name');
    if (name != null) await _run(() => feed.createFamily(name));
  }

  Future<void> _accept() async {
    final token = await _ask('Join a family', 'Invitation code',
        help:
            'Sign in with the email address the invitation was sent to. Only the invited account can use this code.',
        maxLength: 100);
    if (token != null) await _run(() => feed.acceptInvitation(token));
  }

  Future<void> _invite() async {
    final email = await _ask(
        'Invite to ${feed.selected!.name}', 'Email address',
        help:
            'This person needs a Mynube account. An account administrator can create one for them.',
        maxLength: 254);
    if (email == null) return;
    await _run(() async {
      final token = await feed.invite(email);
      if (!mounted) return;
      await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
                  title: const Text('Private invitation'),
                  content: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                            'Share this code privately with the invited person. It expires in 7 days and can be used once.'),
                        const SizedBox(height: 16),
                        SelectableText(token),
                      ]),
                  actions: [
                    FilledButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Done'))
                  ]));
    });
  }

  Future<void> _members() async {
    await _run(() async {
      final family = feed.selected!;
      final members = await feed.members();
      if (!mounted) return;
      await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
                  title: Text(family.name),
                  content: SizedBox(
                      width: 400,
                      child: ListView(
                          shrinkWrap: true,
                          children: members.map((m) {
                            final mine =
                                m['user_id'] == feed.auth.currentUser?.id;
                            final canRemove = m['role'] != 'owner' &&
                                (mine ||
                                    family.role == 'owner' ||
                                    (family.role == 'admin' &&
                                        m['role'] == 'member'));
                            return ListTile(
                                title: Text(m['display_name'] as String),
                                subtitle: Text(m['role'] as String),
                                trailing: canRemove
                                    ? IconButton(
                                        tooltip: mine
                                            ? 'Leave family'
                                            : 'Remove member',
                                        icon: const Icon(
                                            Icons.person_remove_outlined),
                                        onPressed: () async {
                                          final confirmed = await showDialog<
                                                  bool>(
                                              context: dialogContext,
                                              builder: (context) => AlertDialog(
                                                      title: Text(mine
                                                          ? 'Leave this family?'
                                                          : 'Remove this member?'),
                                                      content: const Text(
                                                          'Family feed access will end. Personal originals remain with their owner.'),
                                                      actions: [
                                                        TextButton(
                                                            onPressed: () =>
                                                                Navigator.pop(
                                                                    context,
                                                                    false),
                                                            child: const Text(
                                                                'Cancel')),
                                                        FilledButton(
                                                            onPressed: () =>
                                                                Navigator.pop(
                                                                    context,
                                                                    true),
                                                            child: const Text(
                                                                'Confirm'))
                                                      ]));
                                          if (confirmed == true) {
                                            if (dialogContext.mounted) {
                                              Navigator.pop(dialogContext);
                                            }
                                            await _run(() => feed.removeMember(
                                                m['user_id'] as String));
                                          }
                                        })
                                    : null);
                          }).toList())),
                  actions: [
                    if (family.canInvite)
                      TextButton(
                          onPressed: () {
                            Navigator.pop(dialogContext);
                            _invite();
                          },
                          child: const Text('Invite someone')),
                    TextButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        child: const Text('Done'))
                  ]));
    });
  }

  Future<void> _compose() async {
    await widget.mediaProvider.load();
    if (!mounted) return;
    final choices = widget.mediaProvider.allItems
        .where((m) =>
            m.ownerId == feed.auth.currentUser?.id &&
            m.status == MediaStatus.ready)
        .toList();
    if (choices.isEmpty) {
      _message('Upload a photo or video to your library first.');
      return;
    }
    final caption = TextEditingController();
    final selected = <String>{};
    bool saving = false;
    String? error;
    await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => StatefulBuilder(
            builder: (context, setState) => AlertDialog(
                  title: Text('Share with ${feed.selected!.name}'),
                  content: SizedBox(
                      width: 520,
                      height: MediaQuery.sizeOf(context).height * 0.55,
                      child: Column(children: [
                        const Text(
                            'Only the items you choose will appear in this family’s feed. Your originals remain yours.'),
                        const SizedBox(height: 12),
                        TextField(
                            controller: caption,
                            maxLength: 2000,
                            maxLines: 2,
                            decoration: const InputDecoration(
                                labelText: 'A little context (optional)')),
                        Expanded(
                            child: ListView(
                                children: choices
                                    .map((m) => CheckboxListTile(
                                        value: selected.contains(m.id),
                                        title: Text(m.filename,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis),
                                        secondary: SizedBox(
                                            width: 48,
                                            height: 48,
                                            child: ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(9),
                                                child: VaultImage(
                                                    url: widget.mediaProvider
                                                        .thumbnailUrlFor(m.id),
                                                    label: m.filename))),
                                        onChanged: saving
                                            ? null
                                            : (value) => setState(() {
                                                  if (value == true &&
                                                      selected.length < 20) {
                                                    selected.add(m.id);
                                                  } else {
                                                    selected.remove(m.id);
                                                  }
                                                })))
                                    .toList())),
                        if (error != null)
                          Text(error!,
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.error)),
                        Text('${selected.length} of 20 selected'),
                      ])),
                  actions: [
                    TextButton(
                        onPressed:
                            saving ? null : () => Navigator.pop(dialogContext),
                        child: const Text('Cancel')),
                    FilledButton(
                        onPressed: saving || selected.isEmpty
                            ? null
                            : () async {
                                setState(() {
                                  saving = true;
                                  error = null;
                                });
                                try {
                                  await feed.publish(
                                      caption.text.trim(), selected.toList());
                                  if (dialogContext.mounted) {
                                    Navigator.pop(dialogContext);
                                  }
                                } on ApiException catch (e) {
                                  if (dialogContext.mounted) {
                                    setState(() {
                                      saving = false;
                                      error = e.message;
                                    });
                                  }
                                } catch (_) {
                                  if (dialogContext.mounted) {
                                    setState(() {
                                      saving = false;
                                      error =
                                          'Unable to share. Please try again.';
                                    });
                                  }
                                }
                              },
                        child: Text(saving ? 'Sharing…' : 'Share'))
                  ],
                )));
    WidgetsBinding.instance.addPostFrameCallback((_) => caption.dispose());
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: feed,
      builder: (context, _) {
        final theme = Theme.of(context);
        final colors = theme.colorScheme;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const VaultEyebrow('Close by choice'),
          const SizedBox(height: 8),
          Text('Your circle', style: theme.textTheme.headlineMedium),
          const SizedBox(height: 8),
          Text('Little moments. Your favorite people.',
              style: TextStyle(color: colors.onSurfaceVariant)),
          const SizedBox(height: 24),
          Row(children: [
            if (feed.families.isNotEmpty)
              Expanded(
                  child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                          isExpanded: true,
                          value: feed.selected?.id,
                          style: theme.textTheme.titleSmall,
                          items: feed.families
                              .map((f) => DropdownMenuItem(
                                  value: f.id,
                                  child: Text(f.name,
                                      overflow: TextOverflow.ellipsis)))
                              .toList(),
                          onChanged: feed.loading
                              ? null
                              : (id) {
                                  if (id != null) {
                                    feed.selectFamily(feed.families
                                        .firstWhere((f) => f.id == id));
                                  }
                                })))
            else
              const Spacer(),
            if (feed.selected != null) ...[
              IconButton(
                  tooltip: 'Family members',
                  onPressed: _members,
                  icon: const Icon(Icons.people_outline_rounded, size: 21)),
              const SizedBox(width: 4),
              FilledButton.icon(
                  onPressed: feed.mutating || feed.config.useDemoData
                      ? null
                      : _compose,
                  icon: const Icon(Icons.add_rounded, size: 17),
                  label: const Text('Share'))
            ],
            PopupMenuButton<String>(
                tooltip: 'Circle options',
                onSelected: (value) {
                  if (value == 'create') {
                    _newFamily();
                  } else {
                    _accept();
                  }
                },
                itemBuilder: (_) => const [
                      PopupMenuItem(
                          value: 'create', child: Text('Create a circle')),
                      PopupMenuItem(
                          value: 'join', child: Text('Join with an invitation'))
                    ]),
          ]),
          const SizedBox(height: 10),
          const Divider(),
          if (feed.loading) const LinearProgressIndicator(),
          if (feed.error != null)
            Padding(
                padding: const EdgeInsets.all(12),
                child:
                    Text(feed.error!, style: TextStyle(color: colors.error))),
          Expanded(
              child: feed.posts.isEmpty
                  ? Center(
                      child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 360),
                          child:
                              Column(mainAxisSize: MainAxisSize.min, children: [
                            Container(
                                width: 78,
                                height: 78,
                                decoration: BoxDecoration(
                                    color: colors.primaryContainer,
                                    shape: BoxShape.circle),
                                child: Icon(Icons.favorite_border_rounded,
                                    color: colors.primary, size: 32)),
                            const SizedBox(height: 22),
                            Text('A little closer starts here.',
                                style: theme.textTheme.headlineSmall,
                                textAlign: TextAlign.center),
                            const SizedBox(height: 12),
                            Text(
                                feed.families.isEmpty
                                    ? 'Create a private circle for the people you love. Invite them in, one by one.'
                                    : 'Share a photo, a video, or a little piece of your day. The rest of your vault stays just yours.',
                                style: TextStyle(
                                    color: colors.onSurfaceVariant,
                                    height: 1.7),
                                textAlign: TextAlign.center),
                            const SizedBox(height: 24),
                            if (feed.families.isEmpty)
                              FilledButton(
                                  onPressed: _newFamily,
                                  child: const Text('Create your circle'))
                            else
                              OutlinedButton(
                                  onPressed:
                                      feed.config.useDemoData ? null : _compose,
                                  child: const Text('Share your first moment')),
                          ])))
                  : RefreshIndicator(
                      onRefresh: feed.loadFamilies,
                      child: ListView.builder(
                          padding: const EdgeInsets.only(top: 18, bottom: 32),
                          itemCount: feed.posts.length + (feed.hasMore ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (index == feed.posts.length) {
                              return TextButton(
                                  onPressed: feed.loading
                                      ? null
                                      : () => feed.loadPosts(more: true),
                                  child: const Text('Earlier moments'));
                            }
                            final post = feed.posts[index];
                            return Center(
                                child: ConstrainedBox(
                                    constraints:
                                        const BoxConstraints(maxWidth: 660),
                                    child: VaultEnter(
                                        index: index,
                                        child: _PostCard(
                                            post: post,
                                            provider: feed,
                                            onRemove: () async {
                                              final confirm = await showDialog<
                                                      bool>(
                                                  context: context,
                                                  builder: (context) =>
                                                      AlertDialog(
                                                          title: const Text(
                                                              'Remove this shared moment?'),
                                                          content: const Text(
                                                              'Your original photos and videos will stay in your vault.'),
                                                          actions: [
                                                            TextButton(
                                                                onPressed: () =>
                                                                    Navigator.pop(
                                                                        context,
                                                                        false),
                                                                child: const Text(
                                                                    'Keep it')),
                                                            FilledButton(
                                                                onPressed: () =>
                                                                    Navigator.pop(
                                                                        context,
                                                                        true),
                                                                child: const Text(
                                                                    'Remove post'))
                                                          ]));
                                              if (confirm == true) {
                                                await _run(() =>
                                                    feed.unshare(post.id));
                                              }
                                            }))));
                          }))),
        ]);
      });
}

class _PostCard extends StatefulWidget {
  const _PostCard(
      {required this.post, required this.provider, required this.onRemove});
  final FamilyPost post;
  final FeedProvider provider;
  final VoidCallback onRemove;
  @override
  State<_PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<_PostCard> {
  int _page = 0;
  void _open(Media media) => Navigator.of(context).push(MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => MediaViewer(media: media, provider: widget.provider)));
  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Padding(
        padding: const EdgeInsets.only(bottom: 30),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 2),
              child: Row(children: [
                CircleAvatar(
                    radius: 20,
                    backgroundColor: colors.primaryContainer,
                    foregroundColor: colors.primary,
                    child: Text(
                        post.authorName.isEmpty
                            ? '?'
                            : post.authorName.substring(0, 1),
                        style: const TextStyle(fontWeight: FontWeight.w700))),
                const SizedBox(width: 12),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(post.authorName, style: theme.textTheme.titleSmall),
                      const SizedBox(height: 2),
                      Text(DateFormatter.relative(post.createdAt),
                          style: TextStyle(
                              fontSize: 10, color: colors.onSurfaceVariant))
                    ])),
                if (post.authorId == widget.provider.auth.currentUser?.id)
                  IconButton(
                      tooltip: 'Remove your post',
                      onPressed: widget.onRemove,
                      icon: const Icon(Icons.more_horiz_rounded))
                else
                  Icon(Icons.lock_outline_rounded,
                      size: 14, color: colors.onSurfaceVariant),
              ])),
          ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: AspectRatio(
                  aspectRatio: 1.1,
                  child: Stack(children: [
                    PageView(
                        onPageChanged: (page) => setState(() => _page = page),
                        children: post.media
                            .map((media) => InkWell(
                                onTap: () => _open(media),
                                child: Stack(fit: StackFit.expand, children: [
                                  FutureBuilder<String>(
                                      future: widget.provider
                                          .preview(media.id, size: 'large'),
                                      builder: (context, snapshot) =>
                                          VaultImage(
                                              url: snapshot.data,
                                              label: media.filename)),
                                  if (media.isVideo)
                                    const Center(
                                        child: CircleAvatar(
                                            backgroundColor: Color(0x88000000),
                                            child: Icon(
                                                Icons.play_arrow_rounded,
                                                color: Colors.white))),
                                ])))
                            .toList()),
                    if (post.media.length > 1)
                      Positioned(
                          top: 14,
                          right: 14,
                          child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: .5),
                                  borderRadius: BorderRadius.circular(20)),
                              child: Text('${_page + 1} / ${post.media.length}',
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 11)))),
                  ]))),
          const SizedBox(height: 14),
          Row(children: [
            Icon(Icons.people_outline_rounded, size: 17, color: colors.primary),
            const SizedBox(width: 7),
            Expanded(
                child: Text(
                    'Just for ${widget.provider.selected?.name ?? 'your circle'}',
                    style: TextStyle(
                        fontSize: 10, color: colors.onSurfaceVariant))),
            if (post.media.length > 1)
              Row(
                  children: List.generate(
                      post.media.length,
                      (i) => AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          margin: const EdgeInsets.only(left: 4),
                          width: i == _page ? 14 : 5,
                          height: 5,
                          decoration: BoxDecoration(
                              color: i == _page
                                  ? colors.primary
                                  : colors.outlineVariant,
                              borderRadius: BorderRadius.circular(4))))),
            IconButton(
                tooltip: 'Open memory',
                onPressed: () => _open(post.media[_page]),
                icon: const Icon(Icons.open_in_full_rounded, size: 17)),
          ]),
          if (post.caption.isNotEmpty)
            Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text.rich(
                    TextSpan(children: [
                      TextSpan(
                          text: '${post.authorName}  ',
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      TextSpan(text: post.caption)
                    ]),
                    style: theme.textTheme.bodyMedium)),
        ]));
  }
}
