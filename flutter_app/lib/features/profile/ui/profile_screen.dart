import 'package:flutter/material.dart';

import '../../auth/domain/user.dart';
import '../../directory/providers/family_directory_provider.dart';
import '../../../shared/widgets/user_avatar.dart';
import '../../../shared/utils/date_formatter.dart';
import '../../../shared/utils/file_size_formatter.dart';
import '../providers/profile_provider.dart';
import 'delete_account_button.dart';
import 'change_password_button.dart';
import '../../../shared/widgets/vault_ui.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen(
      {super.key,
      required this.profileProvider,
      required this.familyDirectoryProvider});
  final ProfileProvider profileProvider;
  final FamilyDirectoryProvider familyDirectoryProvider;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: profileProvider,
      builder: (context, _) {
        final theme = Theme.of(context);
        final colors = theme.colorScheme;
        final user = profileProvider.currentUser;
        if (user == null) return const SizedBox.shrink();
        final remaining =
            (user.quotaBytes - user.storageUsed - user.storageReserved)
                .clamp(0, user.quotaBytes);
        return SingleChildScrollView(
            key: const ValueKey<String>('profile-screen'),
            child: Center(
                child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 960),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const VaultEyebrow('A space that feels like you',
                              textAlign: TextAlign.center),
                          const SizedBox(height: 8),
                          Text('Make it yours.',
                              style: theme.textTheme.headlineMedium,
                              textAlign: TextAlign.center),
                          const SizedBox(height: 10),
                          Text(
                              'Your name. Your memories. Your little corner of the world.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: colors.onSurfaceVariant, height: 1.6)),
                          const SizedBox(height: 24),
                          _ProfileIdentity(
                              user: user,
                              profileProvider: profileProvider,
                              directory: familyDirectoryProvider),
                          const SizedBox(height: 20),
                          LayoutBuilder(builder: (context, constraints) {
                            final cards = [
                              _ProfileCard(
                                  key: const ValueKey('profile-name-card'),
                                  title: 'A familiar name',
                                  subtitle: 'What should your circle call you?',
                                  icon: Icons.person_outline_rounded,
                                  child: _DisplayNameEditor(
                                      key: ValueKey(
                                          'display-name-${user.displayName}'),
                                      profileProvider: profileProvider,
                                      initialDisplayName: user.displayName)),
                              _ProfileCard(
                                  key: const ValueKey('profile-storage-card'),
                                  title: 'Room for your memories',
                                  subtitle: 'Your own space, at your own pace.',
                                  icon: Icons.cloud_outlined,
                                  child: Column(children: [
                                    Text(
                                        FileSizeFormatter.compact(
                                            user.storageUsed),
                                        textAlign: TextAlign.center,
                                        style: theme.textTheme.headlineMedium),
                                    const SizedBox(height: 4),
                                    Text(
                                        'of ${FileSizeFormatter.compact(user.quotaBytes)} used',
                                        style: TextStyle(
                                            color: colors.onSurfaceVariant,
                                            fontSize: 12)),
                                    const SizedBox(height: 18),
                                    ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: LinearProgressIndicator(
                                            value: user.storagePct.clamp(0, 1),
                                            minHeight: 7,
                                            backgroundColor:
                                                colors.surfaceContainerHighest,
                                            color: colors.primary)),
                                    const SizedBox(height: 16),
                                    Wrap(
                                        alignment: WrapAlignment.center,
                                        spacing: 24,
                                        runSpacing: 12,
                                        children: [
                                          _ProfileStat(
                                              FileSizeFormatter.compact(
                                                  remaining),
                                              'available'),
                                          _ProfileStat(
                                              FileSizeFormatter.compact(
                                                  user.storageReserved),
                                              'uploading')
                                        ]),
                                    const SizedBox(height: 16),
                                    Text(
                                        'Recently deleted memories use space until they finish deleting.',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                            fontSize: 11,
                                            height: 1.5,
                                            color: colors.onSurfaceVariant)),
                                  ])),
                            ];
                            final paired = constraints.maxWidth >= 700 &&
                                MediaQuery.textScalerOf(context).scale(1) <=
                                    1.3;
                            if (paired) {
                              return IntrinsicHeight(
                                  child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                    Expanded(child: cards[0]),
                                    const SizedBox(width: 20),
                                    Expanded(child: cards[1])
                                  ]));
                            }
                            return Column(children: [
                              cards[0],
                              const SizedBox(height: 20),
                              cards[1]
                            ]);
                          }),
                          const SizedBox(height: 20),
                          _ProfileCard(
                              title: 'Your account, in your hands',
                              subtitle:
                                  'Keep your sign-in personal and your vault yours.',
                              icon: Icons.lock_outline_rounded,
                              child: Column(children: [
                                ChangePasswordButton(
                                    auth: profileProvider.authProvider),
                                const SizedBox(height: 10),
                                Text(
                                    'Changing your password signs out every device.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        color: colors.onSurfaceVariant,
                                        fontSize: 11)),
                                const SizedBox(height: 20),
                                const Divider(),
                                const SizedBox(height: 12),
                                DeleteAccountButton(
                                    auth: profileProvider.authProvider)
                              ])),
                          const SizedBox(height: 32),
                          const VaultEyebrow(
                              'Private by nature. Personal by you.',
                              textAlign: TextAlign.center),
                          const SizedBox(height: 32),
                        ]))));
      });
}

class _ProfileIdentity extends StatelessWidget {
  const _ProfileIdentity(
      {required this.user,
      required this.profileProvider,
      required this.directory});
  final User user;
  final ProfileProvider profileProvider;
  final FamilyDirectoryProvider directory;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final avatar = Container(
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: colors.outlineVariant, width: 1)),
        child: UserAvatar(
            key: ValueKey('profile-avatar-${user.id}'),
            userId: user.id,
            displayName: user.displayName,
            initialAvatarUrl: user.avatarUrl,
            directoryProvider: directory,
            radius: 40));
    final details = Column(mainAxisSize: MainAxisSize.min, children: [
      Text(user.displayName,
          style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
      const SizedBox(height: 6),
      Text(user.email,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: colors.onSurfaceVariant, fontSize: 13)),
      const SizedBox(height: 10),
      Text('Keeping memories since ${DateFormatter.mediumDate(user.createdAt)}',
          textAlign: TextAlign.center,
          style: TextStyle(color: colors.onSurfaceVariant, fontSize: 11)),
    ]);
    final photoButton = OutlinedButton.icon(
        key: const ValueKey<String>('profile-avatar-upload'),
        onPressed:
            profileProvider.isUploadingAvatar || !profileProvider.canPickAvatar
                ? null
                : profileProvider.pickAndUploadAvatar,
        style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14)),
        icon: profileProvider.isUploadingAvatar
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.add_a_photo_outlined, size: 17),
        label: Text(
            profileProvider.isUploadingAvatar
                ? 'Updating photo…'
                : 'Change photo',
            textAlign: TextAlign.center));
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(24),
            child: LayoutBuilder(builder: (context, constraints) {
              final wide = constraints.maxWidth >= 710 &&
                  MediaQuery.textScalerOf(context).scale(1) <= 1.3;
              return Column(mainAxisSize: MainAxisSize.min, children: [
                if (wide)
                  Row(children: [
                    Expanded(child: Center(child: avatar)),
                    Expanded(
                        flex: 3,
                        child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: details)),
                    Expanded(child: photoButton),
                  ])
                else ...[
                  avatar,
                  const SizedBox(height: 18),
                  details,
                  const SizedBox(height: 18),
                  photoButton,
                ],
                if (profileProvider.profileMessage != null)
                  Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: Semantics(
                          liveRegion: true,
                          child: Text(profileProvider.profileMessage!,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: profileProvider.profileMessageIsError
                                      ? colors.error
                                      : colors.onSurfaceVariant,
                                  fontWeight: FontWeight.w600)))),
              ]);
            })));
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard(
      {super.key,
      required this.title,
      required this.subtitle,
      required this.icon,
      required this.child});
  final String title;
  final String subtitle;
  final IconData icon;
  final Widget child;
  @override
  Widget build(BuildContext context) => Card(
      child: SizedBox(
          width: double.infinity,
          child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(icon,
                        size: 22, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(height: 12),
                    Text(title,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 6),
                    Text(subtitle,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 12,
                            height: 1.5,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant)),
                    const SizedBox(height: 24),
                    child
                  ]))));
}

class _ProfileStat extends StatelessWidget {
  const _ProfileStat(this.value, this.label);
  final String value;
  final String label;
  @override
  Widget build(BuildContext context) =>
      Column(mainAxisSize: MainAxisSize.min, children: [
        Text(value, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 3),
        Text(label,
            style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurfaceVariant))
      ]);
}

class _DisplayNameEditor extends StatefulWidget {
  const _DisplayNameEditor({
    super.key,
    required this.profileProvider,
    required this.initialDisplayName,
  });

  final ProfileProvider profileProvider;
  final String initialDisplayName;

  @override
  State<_DisplayNameEditor> createState() => _DisplayNameEditorState();
}

class _DisplayNameEditorState extends State<_DisplayNameEditor> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialDisplayName)
      ..addListener(_handleChanged);
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
    final currentUser = widget.profileProvider.currentUser;
    final currentName = currentUser?.displayName ?? widget.initialDisplayName;
    final isDirty = _controller.text.trim() != currentName.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const ExcludeSemantics(child: Text('Display name')),
        const SizedBox(height: 8),
        Semantics(
            label: 'Display name',
            child: TextField(
              key: const ValueKey<String>('profile-display-name-field'),
              textAlign: TextAlign.center,
              controller: _controller,
              decoration: const InputDecoration(hintText: 'Your name'),
            )),
        const SizedBox(height: 16),
        FilledButton.icon(
          key: const ValueKey<String>('profile-display-name-save'),
          onPressed:
              widget.profileProvider.isSavingProfile || !isDirty ? null : _save,
          icon: widget.profileProvider.isSavingProfile
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.check_rounded, size: 18),
          label: Text(widget.profileProvider.isSavingProfile
              ? 'Saving…'
              : 'Save changes'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    await widget.profileProvider.updateDisplayName(_controller.text);
    if (!mounted) {
      return;
    }

    setState(() {});
  }

  void _handleChanged() {
    if (mounted) {
      setState(() {});
    }
  }
}
