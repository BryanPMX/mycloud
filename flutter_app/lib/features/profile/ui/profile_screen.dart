import 'package:flutter/material.dart';

import '../../directory/providers/family_directory_provider.dart';
import '../../../shared/widgets/user_avatar.dart';
import '../../../shared/utils/date_formatter.dart';
import '../../../shared/utils/file_size_formatter.dart';
import '../providers/profile_provider.dart';
import 'delete_account_button.dart';
import 'change_password_button.dart';
import '../../../shared/widgets/vault_ui.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({
    super.key,
    required this.profileProvider,
    required this.familyDirectoryProvider,
  });

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
                    constraints: const BoxConstraints(maxWidth: 940),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const VaultEyebrow('A space that feels like you'),
                          const SizedBox(height: 8),
                          Text('Make it yours.',
                              style: theme.textTheme.headlineMedium,
                              textAlign: TextAlign.center),
                          const SizedBox(height: 9),
                          Text(
                              'Your name. Your memories. Your little corner of the world.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: colors.onSurfaceVariant, height: 1.6)),
                          const SizedBox(height: 26),
                          Card(
                              child: SizedBox(
                                  width: double.infinity,
                                  child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 24, vertical: 30),
                                      child: Column(children: [
                                        Container(
                                            padding: const EdgeInsets.all(6),
                                            decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                border: Border.all(
                                                    color:
                                                        colors.primaryContainer,
                                                    width: 2)),
                                            child: UserAvatar(
                                                key: ValueKey(
                                                    'profile-avatar-${user.id}'),
                                                userId: user.id,
                                                displayName: user.displayName,
                                                initialAvatarUrl:
                                                    user.avatarUrl,
                                                directoryProvider:
                                                    familyDirectoryProvider,
                                                radius: 43)),
                                        const SizedBox(height: 18),
                                        Text(user.displayName,
                                            style:
                                                theme.textTheme.headlineSmall,
                                            textAlign: TextAlign.center),
                                        const SizedBox(height: 6),
                                        Text(user.email,
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                                color: colors.onSurfaceVariant,
                                                fontSize: 12)),
                                        const SizedBox(height: 18),
                                        OutlinedButton.icon(
                                            key: const ValueKey<String>(
                                                'profile-avatar-upload'),
                                            onPressed: profileProvider
                                                        .isUploadingAvatar ||
                                                    !profileProvider
                                                        .canPickAvatar
                                                ? null
                                                : profileProvider
                                                    .pickAndUploadAvatar,
                                            icon: profileProvider
                                                    .isUploadingAvatar
                                                ? const SizedBox(
                                                    width: 16,
                                                    height: 16,
                                                    child:
                                                        CircularProgressIndicator(
                                                            strokeWidth: 2))
                                                : const Icon(
                                                    Icons.add_a_photo_outlined,
                                                    size: 17),
                                            label: Text(profileProvider
                                                    .isUploadingAvatar
                                                ? 'Updating photo…'
                                                : 'Change photo')),
                                        const SizedBox(height: 12),
                                        Text(
                                            'Keeping memories since ${DateFormatter.mediumDate(user.createdAt)}',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                                color: colors.onSurfaceVariant,
                                                fontSize: 10)),
                                        if (profileProvider.profileMessage !=
                                            null)
                                          Padding(
                                              padding: const EdgeInsets.only(
                                                  top: 14),
                                              child: Semantics(
                                                  liveRegion: true,
                                                  child: Text(
                                                      profileProvider
                                                          .profileMessage!,
                                                      textAlign:
                                                          TextAlign.center,
                                                      style: TextStyle(
                                                          color: profileProvider
                                                                  .profileMessageIsError
                                                              ? colors.error
                                                              : colors
                                                                  .secondary,
                                                          fontWeight: FontWeight
                                                              .w600)))),
                                      ])))),
                          const SizedBox(height: 20),
                          LayoutBuilder(builder: (context, constraints) {
                            final width = constraints.maxWidth >= 700
                                ? (constraints.maxWidth - 20) / 2
                                : constraints.maxWidth;
                            return Wrap(
                                spacing: 20,
                                runSpacing: 20,
                                alignment: WrapAlignment.center,
                                children: [
                                  SizedBox(
                                      width: width,
                                      child: _ProfileCard(
                                          title: 'A familiar name',
                                          subtitle:
                                              'What should your circle call you?',
                                          icon: Icons.person_outline_rounded,
                                          child: _DisplayNameEditor(
                                              key: ValueKey(
                                                  'display-name-${user.displayName}'),
                                              profileProvider: profileProvider,
                                              initialDisplayName:
                                                  user.displayName))),
                                  SizedBox(
                                      width: width,
                                      child: _ProfileCard(
                                          title: 'Room for your memories',
                                          subtitle:
                                              'Your own space, at your own pace.',
                                          icon: Icons.cloud_outlined,
                                          child: Column(children: [
                                            Text(
                                                FileSizeFormatter.compact(
                                                    user.storageUsed),
                                                textAlign: TextAlign.center,
                                                style: theme
                                                    .textTheme.headlineMedium),
                                            Text(
                                                'of ${FileSizeFormatter.compact(user.quotaBytes)} used',
                                                style: TextStyle(
                                                    color:
                                                        colors.onSurfaceVariant,
                                                    fontSize: 12)),
                                            const SizedBox(height: 20),
                                            ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                child: LinearProgressIndicator(
                                                    value: user.storagePct
                                                        .clamp(0, 1),
                                                    minHeight: 7,
                                                    backgroundColor: colors
                                                        .surfaceContainerHighest,
                                                    color: colors.secondary)),
                                            const SizedBox(height: 16),
                                            Wrap(
                                                alignment: WrapAlignment.center,
                                                spacing: 22,
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
                                            const SizedBox(height: 18),
                                            Text(
                                                'Recently deleted memories still use space until they finish deleting.',
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                    fontSize: 10,
                                                    height: 1.6,
                                                    color: colors
                                                        .onSurfaceVariant)),
                                          ]))),
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
                                        fontSize: 10)),
                                const SizedBox(height: 20),
                                const Divider(),
                                const SizedBox(height: 12),
                                DeleteAccountButton(
                                    auth: profileProvider.authProvider)
                              ])),
                          const SizedBox(height: 34),
                          const VaultEyebrow(
                              'Private by nature. Personal by you.'),
                          const SizedBox(height: 32),
                        ]))));
      });
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard(
      {required this.title,
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
                            fontSize: 11,
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
                fontSize: 10,
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
    final theme = Theme.of(context);
    final currentUser = widget.profileProvider.currentUser;
    final currentName = currentUser?.displayName ?? widget.initialDisplayName;
    final isDirty = _controller.text.trim() != currentName.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        TextField(
          key: const ValueKey<String>('profile-display-name-field'),
          textAlign: TextAlign.center,
          controller: _controller,
          decoration: const InputDecoration(
            labelText: 'Display name',
            hintText: 'The name your circle sees',
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          alignment: WrapAlignment.center,
          children: [
            FilledButton.icon(
              key: const ValueKey<String>('profile-display-name-save'),
              onPressed: widget.profileProvider.isSavingProfile || !isDirty
                  ? null
                  : _save,
              icon: widget.profileProvider.isSavingProfile
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_rounded),
              label: Text(
                widget.profileProvider.isSavingProfile ? 'Saving...' : 'Save',
              ),
            ),
            Text(
              'A little more you.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
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
