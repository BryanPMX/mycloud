import 'package:flutter/material.dart';

import '../../directory/providers/family_directory_provider.dart';
import '../../../shared/widgets/user_avatar.dart';
import '../../../shared/utils/date_formatter.dart';
import '../../../shared/utils/file_size_formatter.dart';
import '../providers/profile_provider.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({
    super.key,
    required this.profileProvider,
    required this.familyDirectoryProvider,
  });

  final ProfileProvider profileProvider;
  final FamilyDirectoryProvider familyDirectoryProvider;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: profileProvider,
      builder: (context, _) {
        final theme = Theme.of(context);
        final user = profileProvider.currentUser;

        if (user == null) {
          return const SizedBox.shrink();
        }

        return SingleChildScrollView(
          key: const ValueKey<String>('profile-screen'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 20,
                runSpacing: 20,
                children: [
                  SizedBox(
                    width: 360,
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Account snapshot',
                              style: theme.textTheme.titleLarge,
                            ),
                            const SizedBox(height: 16),
                            _ProfileRow(
                              label: 'Display',
                              value: user.displayName,
                            ),
                            _ProfileRow(label: 'Email', value: user.email),
                            _ProfileRow(label: 'Role', value: user.role.label),
                            _ProfileRow(
                              label: 'Joined',
                              value: DateFormatter.mediumDate(user.createdAt),
                            ),
                            _ProfileRow(
                              label: 'Last login',
                              value: user.lastLoginAt == null
                                  ? 'Unavailable'
                                  : DateFormatter.mediumDateTime(
                                      user.lastLoginAt!,
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 360,
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Avatar upload',
                              style: theme.textTheme.titleLarge,
                            ),
                            const SizedBox(height: 16),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                UserAvatar(
                                  key: ValueKey<String>(
                                      'profile-avatar-${user.id}'),
                                  userId: user.id,
                                  displayName: user.displayName,
                                  initialAvatarUrl: user.avatarUrl,
                                  directoryProvider: familyDirectoryProvider,
                                  radius: 34,
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        user.avatarUrl == null
                                            ? 'No avatar uploaded yet.'
                                            : 'Signed avatar URL cached',
                                        style: theme.textTheme.titleMedium,
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        user.avatarUrl == null
                                            ? 'Upload an image to start serving a short-lived signed avatar URL for this account.'
                                            : 'PUT /users/me/avatar updates the current profile, and cached reads refresh through GET /users/:id/avatar when the signed URL expires.',
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(
                                          color: theme
                                              .colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
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
                                  key: const ValueKey<String>(
                                    'profile-avatar-upload',
                                  ),
                                  onPressed: profileProvider
                                              .isUploadingAvatar ||
                                          !profileProvider.canPickAvatar
                                      ? null
                                      : () {
                                          profileProvider.pickAndUploadAvatar();
                                        },
                                  icon: profileProvider.isUploadingAvatar
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.image_rounded),
                                  label: Text(
                                    profileProvider.isUploadingAvatar
                                        ? 'Uploading...'
                                        : 'Upload avatar',
                                  ),
                                ),
                                Text(
                                  'Current API endpoint: PUT /users/me/avatar',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              profileProvider.avatarPickerHint,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            if (profileProvider.profileMessage != null) ...[
                              const SizedBox(height: 12),
                              Text(
                                profileProvider.profileMessage!,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: profileProvider.profileMessageIsError
                                      ? theme.colorScheme.error
                                      : theme.colorScheme.primary,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 420,
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Profile edits',
                              style: theme.textTheme.titleLarge,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'PATCH /users/me, PUT /users/me/avatar, GET /users/:id/avatar, and GET /users/directory are now wired together so the profile screen reflects the live avatar-read flow instead of showing stored object-key placeholders.',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 16),
                            _DisplayNameEditor(
                              key: ValueKey<String>(
                                'display-name-${user.displayName}',
                              ),
                              profileProvider: profileProvider,
                              initialDisplayName: user.displayName,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 420,
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Storage posture',
                              style: theme.textTheme.titleLarge,
                            ),
                            const SizedBox(height: 16),
                            LinearProgressIndicator(
                              value: user.storagePct.clamp(0, 1),
                              minHeight: 14,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              '${FileSizeFormatter.compact(user.storageUsed)} of ${FileSizeFormatter.compact(user.quotaBytes)} used',
                              style: theme.textTheme.bodyLarge,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${(user.storagePct * 100).toStringAsFixed(1)}% of quota currently allocated.',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Recommended next Flutter slices',
                        style: theme.textTheme.titleLarge,
                      ),
                      const SizedBox(height: 16),
                      ...profileProvider.rolloutSteps.map(
                        (step) => Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                step.done
                                    ? Icons.check_circle_rounded
                                    : Icons.radio_button_unchecked_rounded,
                                color: step.done
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      step.title,
                                      style: theme.textTheme.titleMedium,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      step.description,
                                      style:
                                          theme.textTheme.bodyMedium?.copyWith(
                                        color:
                                            theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Deployment endpoints',
                        style: theme.textTheme.titleLarge,
                      ),
                      const SizedBox(height: 16),
                      ...profileProvider.endpoints.map(
                        (endpoint) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _ProfileRow(
                            label: endpoint.label,
                            value: endpoint.uri.toString(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          key: const ValueKey<String>('profile-display-name-field'),
          controller: _controller,
          decoration: const InputDecoration(
            labelText: 'Display name',
            hintText: 'How other family members see you',
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
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
              'Current API endpoint: PATCH /users/me',
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

class _ProfileRow extends StatelessWidget {
  const _ProfileRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(value, style: theme.textTheme.bodyLarge),
        ],
      ),
    );
  }
}
