import 'package:flutter/material.dart';

import '../../../shared/utils/date_formatter.dart';
import '../../../shared/utils/file_size_formatter.dart';
import '../../auth/domain/user.dart';
import '../domain/admin_user.dart';
import '../providers/admin_dashboard_provider.dart';

class AdminDashboardScreen extends StatelessWidget {
  const AdminDashboardScreen({super.key, required this.adminProvider});

  final AdminDashboardProvider adminProvider;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: adminProvider,
      builder: (context, _) {
        final theme = Theme.of(context);
        final stats = adminProvider.stats;

        return SingleChildScrollView(
          key: const ValueKey<String>('admin-dashboard-screen'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (adminProvider.errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    adminProvider.errorMessage!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
              if (adminProvider.actionMessage != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    adminProvider.actionMessage!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: adminProvider.actionMessageIsError
                          ? theme.colorScheme.error
                          : theme.colorScheme.primary,
                    ),
                  ),
                ),
              Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  _StatCard(
                    title: 'Users',
                    value: '${stats.activeUsers}/${stats.totalUsers}',
                    detail: 'Active accounts',
                  ),
                  _StatCard(
                    title: 'Storage',
                    value: '${(stats.pctUsed * 100).toStringAsFixed(1)}%',
                    detail:
                        '${FileSizeFormatter.compact(stats.usedBytes)} of ${FileSizeFormatter.compact(stats.totalBytes)}',
                  ),
                  _StatCard(
                    title: 'Media',
                    value: '${stats.totalItems}',
                    detail:
                        '${stats.totalImages} images · ${stats.totalVideos} videos',
                  ),
                  _StatCard(
                    title: 'Jobs',
                    value: '${stats.pendingJobs}',
                    detail: adminProvider.isLoading
                        ? 'Refreshing from /admin/stats'
                        : 'Pending worker tasks',
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
                        'Invite family member',
                        style: theme.textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'POST /admin/users/invite now has a real operator surface, including the fallback invite URL returned by the backend.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _InviteUserForm(adminProvider: adminProvider),
                      if (adminProvider.latestInvite != null) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            color: theme.colorScheme.primaryContainer
                                .withValues(alpha: 0.35),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Latest invite',
                                style: theme.textTheme.titleMedium,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                adminProvider.latestInvite!.inviteUrl,
                                style: theme.textTheme.bodyMedium,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Expires ${DateFormatter.mediumDateTime(adminProvider.latestInvite!.expiresAt)}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
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
                      Wrap(
                        spacing: 16,
                        runSpacing: 12,
                        alignment: WrapAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Account management',
                                style: theme.textTheme.titleLarge,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'GET /admin/users plus PATCH/DELETE /admin/users/:id are now surfaced as editable account cards.',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                          OutlinedButton.icon(
                            onPressed: adminProvider.isLoadingUsers
                                ? null
                                : () {
                                    adminProvider.loadUsers();
                                  },
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('Refresh users'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (adminProvider.isLoadingUsers &&
                          adminProvider.users.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (adminProvider.users.isEmpty)
                        Text(
                          'No admin users loaded yet.',
                          style: theme.textTheme.bodyMedium,
                        )
                      else
                        ...adminProvider.users.map(
                          (user) => Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: _AdminUserCard(
                              user: user,
                              adminProvider: adminProvider,
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
                        'Recent backend delivery from repository logs',
                        style: theme.textTheme.titleLarge,
                      ),
                      const SizedBox(height: 16),
                      ...adminProvider.recentBackendLogs.map(
                        (entry) => Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 120,
                                child: Text(
                                  entry.dateLabel,
                                  style: theme.textTheme.labelLarge?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      entry.title,
                                      style: theme.textTheme.titleMedium,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      entry.description,
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
                        'What Flutter should continue next',
                        style: theme.textTheme.titleLarge,
                      ),
                      const SizedBox(height: 16),
                      ...adminProvider.nextFlutterContinuations.map(
                        (item) => Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(20),
                              color: item.isHighestPriority
                                  ? theme.colorScheme.primaryContainer
                                      .withValues(alpha: 0.45)
                                  : theme.colorScheme.surfaceContainerHighest
                                      .withValues(alpha: 0.35),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  item.isHighestPriority
                                      ? Icons.priority_high_rounded
                                      : Icons.arrow_forward_rounded,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.title,
                                        style: theme.textTheme.titleMedium,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(item.description),
                                    ],
                                  ),
                                ),
                              ],
                            ),
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

class _InviteUserForm extends StatefulWidget {
  const _InviteUserForm({required this.adminProvider});

  final AdminDashboardProvider adminProvider;

  @override
  State<_InviteUserForm> createState() => _InviteUserFormState();
}

class _InviteUserFormState extends State<_InviteUserForm> {
  late final TextEditingController _emailController;
  late final TextEditingController _quotaController;
  UserRole _role = UserRole.member;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController();
    _quotaController = TextEditingController(text: '20');
  }

  @override
  void dispose() {
    _emailController.dispose();
    _quotaController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.end,
      children: [
        SizedBox(
          width: 280,
          child: TextField(
            key: const ValueKey<String>('admin-invite-email'),
            controller: _emailController,
            decoration: const InputDecoration(
              labelText: 'Email',
              hintText: 'newmember@family.com',
            ),
          ),
        ),
        SizedBox(
          width: 160,
          child: DropdownButtonFormField<UserRole>(
            initialValue: _role,
            decoration: const InputDecoration(labelText: 'Role'),
            items: UserRole.values
                .map(
                  (role) => DropdownMenuItem<UserRole>(
                    value: role,
                    child: Text(role.label),
                  ),
                )
                .toList(growable: false),
            onChanged: (value) {
              if (value == null) {
                return;
              }
              setState(() {
                _role = value;
              });
            },
          ),
        ),
        SizedBox(
          width: 140,
          child: TextField(
            controller: _quotaController,
            decoration: const InputDecoration(labelText: 'Quota (GB)'),
            keyboardType: TextInputType.number,
          ),
        ),
        FilledButton.icon(
          key: const ValueKey<String>('admin-invite-submit'),
          onPressed: widget.adminProvider.isInviting ? null : _submit,
          icon: widget.adminProvider.isInviting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.mail_outline_rounded),
          label: Text(
            widget.adminProvider.isInviting ? 'Creating...' : 'Create invite',
          ),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    final quotaGb = int.tryParse(_quotaController.text.trim());
    if (quotaGb == null) {
      return;
    }

    final success = await widget.adminProvider.inviteUser(
      email: _emailController.text,
      role: _role,
      quotaGb: quotaGb,
    );
    if (!mounted || !success) {
      return;
    }

    _emailController.clear();
    _quotaController.text = _role == UserRole.admin ? '100' : '20';
    setState(() {
      _role = UserRole.member;
    });
  }
}

class _AdminUserCard extends StatefulWidget {
  const _AdminUserCard({
    required this.user,
    required this.adminProvider,
  });

  final AdminUser user;
  final AdminDashboardProvider adminProvider;

  @override
  State<_AdminUserCard> createState() => _AdminUserCardState();
}

class _AdminUserCardState extends State<_AdminUserCard> {
  static const int _oneGigabyte = 1024 * 1024 * 1024;

  late final TextEditingController _quotaController;
  late UserRole _role;
  late bool _active;

  @override
  void initState() {
    super.initState();
    _role = widget.user.role;
    _active = widget.user.active;
    _quotaController = TextEditingController(
      text: '${(widget.user.quotaBytes / _oneGigabyte).round()}',
    );
  }

  @override
  void didUpdateWidget(covariant _AdminUserCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.user.id != widget.user.id ||
        oldWidget.user.quotaBytes != widget.user.quotaBytes ||
        oldWidget.user.role != widget.user.role ||
        oldWidget.user.active != widget.user.active) {
      _role = widget.user.role;
      _active = widget.user.active;
      _quotaController.text =
          '${(widget.user.quotaBytes / _oneGigabyte).round()}';
    }
  }

  @override
  void dispose() {
    _quotaController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCurrentUser = widget.adminProvider.isCurrentUser(widget.user.id);
    final isSaving = widget.adminProvider.isSavingUser(widget.user.id);
    final isDeactivating =
        widget.adminProvider.isDeactivatingUser(widget.user.id);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color:
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(widget.user.displayName, style: theme.textTheme.titleLarge),
              Chip(
                label: Text(widget.user.active ? 'active' : 'inactive'),
              ),
              if (isCurrentUser)
                Chip(
                  label: const Text('current admin'),
                  avatar: const Icon(Icons.shield_outlined, size: 18),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            widget.user.email,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              SizedBox(
                width: 180,
                child: DropdownButtonFormField<UserRole>(
                  initialValue: _role,
                  decoration: const InputDecoration(labelText: 'Role'),
                  items: UserRole.values
                      .map(
                        (role) => DropdownMenuItem<UserRole>(
                          value: role,
                          child: Text(role.label),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: isCurrentUser
                      ? null
                      : (value) {
                          if (value == null) {
                            return;
                          }
                          setState(() {
                            _role = value;
                          });
                        },
                ),
              ),
              SizedBox(
                width: 140,
                child: TextField(
                  controller: _quotaController,
                  decoration: const InputDecoration(labelText: 'Quota (GB)'),
                  keyboardType: TextInputType.number,
                ),
              ),
              SizedBox(
                width: 220,
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Account active'),
                  value: _active,
                  onChanged: isCurrentUser
                      ? null
                      : (value) {
                          setState(() {
                            _active = value;
                          });
                        },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 14,
            runSpacing: 8,
            children: [
              Text(
                'Used ${FileSizeFormatter.compact(widget.user.storageUsed)}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              Text(
                'Created ${DateFormatter.mediumDate(widget.user.createdAt)}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              Text(
                widget.user.lastLoginAt == null
                    ? 'Last login unavailable'
                    : 'Last login ${DateFormatter.mediumDateTime(widget.user.lastLoginAt!)}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.icon(
                key: ValueKey<String>('admin-user-save-${widget.user.id}'),
                onPressed: isSaving || isDeactivating ? null : _save,
                icon: isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_rounded),
                label: Text(isSaving ? 'Saving...' : 'Save changes'),
              ),
              TextButton.icon(
                key:
                    ValueKey<String>('admin-user-deactivate-${widget.user.id}'),
                onPressed: isCurrentUser ||
                        !widget.user.active ||
                        isSaving ||
                        isDeactivating
                    ? null
                    : () {
                        widget.adminProvider.deactivateUser(widget.user.id);
                      },
                icon: isDeactivating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.person_off_outlined),
                label: const Text('Deactivate'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final parsedQuotaGb = int.tryParse(_quotaController.text.trim());
    if (parsedQuotaGb == null || parsedQuotaGb <= 0) {
      return;
    }

    final isCurrentUser = widget.adminProvider.isCurrentUser(widget.user.id);
    final roleChanged =
        !isCurrentUser && _role != widget.user.role ? _role : null;
    final quotaBytes = parsedQuotaGb * _oneGigabyte;
    final quotaChanged =
        quotaBytes != widget.user.quotaBytes ? quotaBytes : null;
    final activeChanged =
        !isCurrentUser && _active != widget.user.active ? _active : null;

    final saved = await widget.adminProvider.updateUser(
      userId: widget.user.id,
      role: roleChanged,
      quotaBytes: quotaChanged,
      active: activeChanged,
    );
    if (!mounted || !saved) {
      return;
    }

    setState(() {});
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.title,
    required this.value,
    required this.detail,
  });

  final String title;
  final String value;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      width: 220,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 10),
              Text(value, style: theme.textTheme.headlineMedium),
              const SizedBox(height: 6),
              Text(detail),
            ],
          ),
        ),
      ),
    );
  }
}
