import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../shared/utils/date_formatter.dart';
import '../../../shared/utils/file_size_formatter.dart';
import '../../../shared/widgets/vault_ui.dart';
import '../../auth/domain/user.dart';
import '../domain/admin_user.dart';
import '../providers/admin_dashboard_provider.dart';

const _gib = 1024 * 1024 * 1024;
String _roleName(UserRole role) =>
    role == UserRole.admin ? 'Administrator' : 'Member';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key, required this.adminProvider});
  final AdminDashboardProvider adminProvider;
  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final _search = TextEditingController();
  String _filter = 'all';
  AdminDashboardProvider get admin => widget.adminProvider;

  @override
  void initState() {
    super.initState();
    _search.addListener(_changed);
  }

  void _changed() => setState(() {});
  @override
  void dispose() {
    _search.removeListener(_changed);
    _search.dispose();
    super.dispose();
  }

  void _invite() => showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _InviteDialog(admin: admin));
  void _edit(AdminUser user) => showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _EditAccountDialog(admin: admin, user: user));

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: admin,
      builder: (context, _) {
        final theme = Theme.of(context);
        final colors = theme.colorScheme;
        final stats = admin.stats;
        final query = _search.text.trim().toLowerCase();
        final users = admin.users
            .where((u) =>
                ('${u.displayName} ${u.email}').toLowerCase().contains(query) &&
                (_filter == 'all' ||
                    (_filter == 'active' ? u.active : !u.active)))
            .toList();
        final loaded = admin.hasLoaded;
        return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1200),
                child: VaultSection(
                  key: const ValueKey('admin-dashboard-screen'),
                  eyebrow: 'Care for your space',
                  title: 'Your people',
                  subtitle: 'Manage access. Make room for memories.',
                  toolbar: LayoutBuilder(
                      builder: (context, constraints) => Row(children: [
                            Expanded(
                                child: Text(
                                    admin.hasLoadedUsers
                                        ? '${admin.users.length} ${admin.users.length == 1 ? 'account' : 'accounts'}'
                                        : 'Accounts',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color: colors.onSurfaceVariant))),
                            IconButton(
                                tooltip: 'Refresh overview',
                                onPressed: admin.isLoading ? null : admin.load,
                                icon: const Icon(Icons.refresh_rounded,
                                    size: 21)),
                            const SizedBox(width: 4),
                            FilledButton.icon(
                                key: const ValueKey('admin-open-invite'),
                                onPressed: admin.isInviting ? null : _invite,
                                icon: const Icon(Icons.person_add_alt_1_rounded,
                                    size: 18),
                                label: Text(constraints.maxWidth < 500
                                    ? 'Invite'
                                    : 'Invite someone')),
                          ])),
                  child: RefreshIndicator(
                      onRefresh: admin.load,
                      child: VaultSectionBody(
                          maxWidth: 1200,
                          scrollKey: const ValueKey('admin-content-scroll'),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (admin.errorMessage != null) ...[
                                  _Notice(
                                      text: admin.errorMessage!, error: true),
                                  const SizedBox(height: 16)
                                ],
                                if (admin.actionMessage != null) ...[
                                  _Notice(
                                      text: admin.actionMessage!,
                                      error: admin.actionMessageIsError),
                                  const SizedBox(height: 16)
                                ],
                                _OverviewGrid(cards: [
                                  _StatCard(
                                      icon: Icons.people_outline_rounded,
                                      title: 'Accounts',
                                      value:
                                          loaded ? '${stats.totalUsers}' : '—',
                                      detail: loaded
                                          ? '${stats.activeUsers} can sign in'
                                          : 'Waiting for your overview'),
                                  _StatCard(
                                      icon: Icons.cloud_outlined,
                                      title: 'Space used',
                                      value: loaded
                                          ? FileSizeFormatter.compact(
                                              stats.usedBytes)
                                          : '—',
                                      detail: loaded
                                          ? 'of ${FileSizeFormatter.compact(stats.totalBytes)} allocated'
                                          : 'Waiting for your overview'),
                                  _StatCard(
                                      icon: Icons.photo_library_outlined,
                                      title: 'Memories',
                                      value:
                                          loaded ? '${stats.totalItems}' : '—',
                                      detail: loaded
                                          ? '${stats.totalImages} photos · ${stats.totalVideos} videos'
                                          : 'Waiting for your overview'),
                                  _StatCard(
                                      icon: Icons.auto_awesome_outlined,
                                      title: 'In progress',
                                      value:
                                          loaded ? '${stats.pendingJobs}' : '—',
                                      detail: loaded
                                          ? (stats.pendingJobs == 0
                                              ? 'No tasks waiting'
                                              : 'Waiting or processing')
                                          : 'Waiting for your overview'),
                                ]),
                                if (admin.latestInvite != null) ...[
                                  const SizedBox(height: 20),
                                  Card(
                                      child: Padding(
                                          padding: const EdgeInsets.all(20),
                                          child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Row(children: [
                                                  Icon(Icons.link_rounded,
                                                      color: colors.primary),
                                                  const SizedBox(width: 10),
                                                  Expanded(
                                                      child: Text(
                                                          'Invitation ready',
                                                          style: theme.textTheme
                                                              .titleMedium)),
                                                  IconButton(
                                                      tooltip:
                                                          'Copy invitation link',
                                                      onPressed: () async {
                                                        await Clipboard.setData(
                                                            ClipboardData(
                                                                text: admin
                                                                    .latestInvite!
                                                                    .inviteUrl));
                                                        if (context.mounted) {
                                                          ScaffoldMessenger.of(
                                                                  context)
                                                              .showSnackBar(
                                                                  const SnackBar(
                                                                      content: Text(
                                                                          'Invitation link copied.')));
                                                        }
                                                      },
                                                      icon: const Icon(
                                                          Icons.copy_outlined,
                                                          size: 20)),
                                                ]),
                                                const SizedBox(height: 8),
                                                const Text(
                                                    'Share this link privately with the person you invited.'),
                                                const SizedBox(height: 12),
                                                SelectableText(
                                                    admin.latestInvite!
                                                        .inviteUrl,
                                                    style: theme
                                                        .textTheme.bodySmall),
                                                const SizedBox(height: 10),
                                                Text(
                                                    'Expires ${DateFormatter.mediumDateTime(admin.latestInvite!.expiresAt.toLocal())}',
                                                    style: TextStyle(
                                                        fontSize: 12,
                                                        color: colors
                                                            .onSurfaceVariant)),
                                              ]))),
                                ],
                                const SizedBox(height: 20),
                                Card(
                                    semanticContainer: false,
                                    child: Padding(
                                        padding: EdgeInsets.all(
                                            MediaQuery.sizeOf(context).width <
                                                    600
                                                ? 16
                                                : 24),
                                        child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [
                                              Text('People in your space',
                                                  style: theme
                                                      .textTheme.titleLarge),
                                              const SizedBox(height: 6),
                                              Text(
                                                  'Individual accounts. Their own memories. Room to belong.',
                                                  style: TextStyle(
                                                      color: colors
                                                          .onSurfaceVariant)),
                                              const SizedBox(height: 20),
                                              TextField(
                                                  key: const ValueKey(
                                                      'admin-search'),
                                                  controller: _search,
                                                  decoration: const InputDecoration(
                                                      hintText:
                                                          'Search by name or email',
                                                      prefixIcon: Icon(
                                                          Icons.search_rounded,
                                                          size: 21))),
                                              const SizedBox(height: 12),
                                              SingleChildScrollView(
                                                  scrollDirection:
                                                      Axis.horizontal,
                                                  child: Row(children: [
                                                    for (final filter in const [
                                                      ('all', 'Everyone'),
                                                      ('active', 'Can sign in'),
                                                      ('inactive', 'Access off')
                                                    ]) ...[
                                                      VaultPill(filter.$2,
                                                          selected: _filter ==
                                                              filter.$1,
                                                          onTap: () => setState(
                                                              () => _filter =
                                                                  filter.$1)),
                                                      const SizedBox(width: 8)
                                                    ],
                                                  ])),
                                              const SizedBox(height: 20),
                                              if (admin.isLoadingUsers &&
                                                  admin.users.isEmpty)
                                                const Padding(
                                                    padding: EdgeInsets.all(24),
                                                    child: Center(
                                                        child:
                                                            CircularProgressIndicator()))
                                              else if (users.isEmpty)
                                                Padding(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                        vertical: 28),
                                                    child: Column(children: [
                                                      Icon(
                                                          Icons
                                                              .person_search_outlined,
                                                          size: 32,
                                                          color: colors
                                                              .onSurfaceVariant),
                                                      const SizedBox(
                                                          height: 12),
                                                      Text(
                                                          admin.users.isEmpty
                                                              ? 'No accounts to show yet.'
                                                              : 'No matching accounts.',
                                                          textAlign:
                                                              TextAlign.center,
                                                          style: theme.textTheme
                                                              .titleMedium),
                                                      if (query.isNotEmpty ||
                                                          _filter != 'all')
                                                        TextButton(
                                                            onPressed: () {
                                                              _search.clear();
                                                              setState(() =>
                                                                  _filter =
                                                                      'all');
                                                            },
                                                            child: const Text(
                                                                'Clear search and filters')),
                                                    ]))
                                              else
                                                for (var i = 0;
                                                    i < users.length;
                                                    i++) ...[
                                                  if (i > 0)
                                                    const Padding(
                                                        padding: EdgeInsets
                                                            .symmetric(
                                                                vertical: 20),
                                                        child: Divider()),
                                                  _AccountRow(
                                                      key: ValueKey(
                                                          'admin-account-${users[i].id}'),
                                                      user: users[i],
                                                      isCurrent:
                                                          admin.isCurrentUser(
                                                              users[i].id),
                                                      onManage: () =>
                                                          _edit(users[i])),
                                                ],
                                              const SizedBox(height: 24),
                                              const Divider(),
                                              const SizedBox(height: 16),
                                              Row(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Icon(
                                                        Icons
                                                            .lock_outline_rounded,
                                                        size: 16,
                                                        color: colors
                                                            .onSurfaceVariant),
                                                    const SizedBox(width: 8),
                                                    Expanded(
                                                        child: Text(
                                                            'Private vaults stay private, including from administrators.',
                                                            style: TextStyle(
                                                                color: colors
                                                                    .onSurfaceVariant,
                                                                fontSize: 12,
                                                                height: 1.5))),
                                                  ]),
                                            ]))),
                              ]))),
                )));
      });
}

class _OverviewGrid extends StatelessWidget {
  const _OverviewGrid({required this.cards});
  final List<Widget> cards;
  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        final columns = MediaQuery.textScalerOf(context).scale(1) > 1.3
            ? 1
            : constraints.maxWidth >= 950
                ? 4
                : constraints.maxWidth >= 320
                    ? 2
                    : 1;
        return Column(children: [
          for (var start = 0; start < cards.length; start += columns) ...[
            if (start > 0) const SizedBox(height: 12),
            IntrinsicHeight(
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                  for (var n = 0;
                      n < columns && start + n < cards.length;
                      n++) ...[
                    if (n > 0) const SizedBox(width: 12),
                    Expanded(child: cards[start + n]),
                  ],
                ])),
          ],
        ]);
      });
}

class _StatCard extends StatelessWidget {
  const _StatCard(
      {required this.icon,
      required this.title,
      required this.value,
      required this.detail});
  final IconData icon;
  final String title, value, detail;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(18),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(icon, size: 21, color: theme.colorScheme.primary),
              const SizedBox(height: 14),
              Text(title,
                  style: TextStyle(
                      fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
              const SizedBox(height: 6),
              Text(value, style: theme.textTheme.headlineSmall),
              const SizedBox(height: 6),
              Text(detail,
                  style: TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: theme.colorScheme.onSurfaceVariant)),
            ])));
  }
}

class _AccountRow extends StatelessWidget {
  const _AccountRow(
      {super.key,
      required this.user,
      required this.isCurrent,
      required this.onManage});
  final AdminUser user;
  final bool isCurrent;
  final VoidCallback onManage;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final parts = user.displayName
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    final initials = parts.isEmpty
        ? '?'
        : (parts.first.characters.first +
                (parts.length > 1 ? parts.last.characters.first : ''))
            .toUpperCase();
    final usage =
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(
          '${FileSizeFormatter.compact(user.storageUsed)} of ${FileSizeFormatter.compact(user.quotaBytes)} used',
          style: theme.textTheme.bodySmall),
      const SizedBox(height: 8),
      ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
              value: user.quotaBytes <= 0
                  ? 0
                  : (user.storageUsed / user.quotaBytes).clamp(0, 1),
              minHeight: 6,
              backgroundColor: colors.surfaceContainerHighest,
              color: user.storageUsed > user.quotaBytes
                  ? colors.error
                  : colors.primary)),
    ]);
    final lastSeen = Text(
        user.lastLoginAt == null
            ? 'No sign-ins yet'
            : 'Last sign-in ${DateFormatter.mediumDate(user.lastLoginAt!.toLocal())}',
        style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        CircleAvatar(
            radius: 21,
            backgroundColor: colors.primaryContainer,
            foregroundColor: colors.onSurface,
            child: Text(initials,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700))),
        const SizedBox(width: 12),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(user.displayName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(user.email,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant)),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            _Badge(_roleName(user.role)),
            if (isCurrent) const _Badge('You'),
            if (!user.active) const _Badge('Access off'),
          ]),
        ])),
        const SizedBox(width: 8),
        IconButton(
            key: ValueKey('admin-user-manage-${user.id}'),
            tooltip: 'Manage ${user.displayName}',
            onPressed: onManage,
            icon: const Icon(Icons.tune_rounded, size: 20)),
      ]),
      const SizedBox(height: 16),
      LayoutBuilder(
          builder: (context, constraints) => constraints.maxWidth >= 600
              ? Row(children: [
                  Expanded(child: usage),
                  const SizedBox(width: 28),
                  lastSeen
                ])
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [usage, const SizedBox(height: 12), lastSeen])),
    ]);
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(6)),
      child: Text(text,
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600)));
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text, this.error = false});
  final String text;
  final bool error;
  @override
  Widget build(BuildContext context) => Semantics(
      liveRegion: true,
      child: Text(text,
          style: TextStyle(
              color: error
                  ? Theme.of(context).colorScheme.error
                  : Theme.of(context).colorScheme.onSurfaceVariant,
              height: 1.5)));
}

class _Field extends StatelessWidget {
  const _Field(this.label, this.child);
  final String label;
  final Widget child;
  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ExcludeSemantics(
            child: Text(label, style: Theme.of(context).textTheme.labelLarge)),
        const SizedBox(height: 8),
        Semantics(label: label, child: child),
      ]);
}

class _RoleAndQuotaFields extends StatelessWidget {
  const _RoleAndQuotaFields(
      {required this.role,
      required this.onRole,
      required this.quota,
      required this.quotaValidator,
      this.enabled = true,
      this.roleKey,
      this.quotaKey});
  final UserRole role;
  final ValueChanged<UserRole?>? onRole;
  final TextEditingController quota;
  final String? Function(String?) quotaValidator;
  final bool enabled;
  final Key? roleKey, quotaKey;
  @override
  Widget build(BuildContext context) {
    final roleField = _Field(
        'Account role',
        DropdownButtonFormField<UserRole>(
            key: roleKey,
            initialValue: role,
            isExpanded: true,
            items: UserRole.values
                .map((r) => DropdownMenuItem(
                    value: r,
                    child: Text(_roleName(r), overflow: TextOverflow.ellipsis)))
                .toList(),
            onChanged: enabled ? onRole : null));
    final quotaField = _Field(
        'Storage limit (GB)',
        TextFormField(
            key: quotaKey,
            controller: quota,
            enabled: enabled,
            keyboardType: TextInputType.number,
            validator: quotaValidator,
            decoration: const InputDecoration(hintText: '20')));
    return LayoutBuilder(
        builder: (context, constraints) => constraints.maxWidth >= 420 &&
                MediaQuery.textScalerOf(context).scale(1) <= 1.3
            ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: roleField),
                const SizedBox(width: 16),
                Expanded(child: quotaField)
              ])
            : Column(
                children: [roleField, const SizedBox(height: 18), quotaField]));
  }
}

class _InviteDialog extends StatefulWidget {
  const _InviteDialog({required this.admin});
  final AdminDashboardProvider admin;
  @override
  State<_InviteDialog> createState() => _InviteDialogState();
}

class _InviteDialogState extends State<_InviteDialog> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _quota = TextEditingController(text: '20');
  UserRole _role = UserRole.member;
  @override
  void dispose() {
    _email.dispose();
    _quota.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    final ok = await widget.admin.inviteUser(
        email: _email.text,
        role: _role,
        quotaGb: int.parse(_quota.text.trim()));
    if (mounted && ok) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: widget.admin,
      builder: (context, _) {
        final busy = widget.admin.isInviting;
        return AlertDialog(
            title: const Text('Invite someone'),
            content: SizedBox(
                width: 480,
                child: SingleChildScrollView(
                    child: Form(
                        key: _form,
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                  'A personal account, a private vault, and a little space of their own.'),
                              const SizedBox(height: 22),
                              _Field(
                                  'Email address',
                                  TextFormField(
                                      key: const ValueKey('admin-invite-email'),
                                      controller: _email,
                                      enabled: !busy,
                                      keyboardType: TextInputType.emailAddress,
                                      autofillHints: const [
                                        AutofillHints.email
                                      ],
                                      decoration: const InputDecoration(
                                          hintText: 'someone@example.com'),
                                      validator: (value) => RegExp(
                                                  r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                                              .hasMatch(value?.trim() ?? '')
                                          ? null
                                          : 'Enter a valid email address.')),
                              const SizedBox(height: 18),
                              _RoleAndQuotaFields(
                                  role: _role,
                                  onRole: (r) {
                                    if (r != null) setState(() => _role = r);
                                  },
                                  quota: _quota,
                                  enabled: !busy,
                                  quotaValidator: (v) =>
                                      (int.tryParse(v?.trim() ?? '') ?? 0) > 0
                                          ? null
                                          : 'Enter a limit greater than zero.'),
                              if (widget.admin.actionMessageIsError &&
                                  widget.admin.actionMessage != null) ...[
                                const SizedBox(height: 16),
                                _Notice(
                                    text: widget.admin.actionMessage!,
                                    error: true)
                              ],
                            ])))),
            actions: [
              TextButton(
                  onPressed: busy ? null : () => Navigator.pop(context),
                  child: const Text('Cancel')),
              FilledButton.icon(
                  key: const ValueKey('admin-invite-submit'),
                  onPressed: busy ? null : _submit,
                  icon: busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.mail_outline_rounded, size: 18),
                  label: Text(busy ? 'Creating…' : 'Create invitation')),
            ]);
      });
}

class _EditAccountDialog extends StatefulWidget {
  const _EditAccountDialog({required this.admin, required this.user});
  final AdminDashboardProvider admin;
  final AdminUser user;
  @override
  State<_EditAccountDialog> createState() => _EditAccountDialogState();
}

class _EditAccountDialogState extends State<_EditAccountDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _quota;
  late final String _initialQuota;
  late UserRole _role;
  late bool _active;
  @override
  void initState() {
    super.initState();
    _initialQuota = '${(widget.user.quotaBytes / _gib).ceil()}';
    _quota = TextEditingController(text: _initialQuota)..addListener(_changed);
    _role = widget.user.role;
    _active = widget.user.active;
  }

  void _changed() => setState(() {});
  @override
  void dispose() {
    _quota.removeListener(_changed);
    _quota.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final self = widget.admin.isCurrentUser(widget.user.id);
    final ok = await widget.admin.updateUser(
        userId: widget.user.id,
        role: !self && _role != widget.user.role ? _role : null,
        active: !self && _active != widget.user.active ? _active : null,
        quotaBytes: _quota.text.trim() != _initialQuota
            ? int.parse(_quota.text.trim()) * _gib
            : null);
    if (mounted && ok) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: widget.admin,
      builder: (context, _) {
        final user = widget.user;
        final self = widget.admin.isCurrentUser(user.id);
        final busy = widget.admin.isSavingUser(user.id);
        final dirty = _quota.text.trim() != _initialQuota ||
            (!self && (_role != user.role || _active != user.active));
        return AlertDialog(
            title: const Text('Manage account'),
            content: SizedBox(
                width: 480,
                child: SingleChildScrollView(
                    child: Form(
                        key: _form,
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(user.displayName,
                                  style:
                                      Theme.of(context).textTheme.titleMedium),
                              const SizedBox(height: 4),
                              Text(user.email,
                                  style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant)),
                              const SizedBox(height: 22),
                              _RoleAndQuotaFields(
                                  role: _role,
                                  onRole: self
                                      ? null
                                      : (r) {
                                          if (r != null) {
                                            setState(() => _role = r);
                                          }
                                        },
                                  roleKey:
                                      ValueKey('admin-user-role-${user.id}'),
                                  quotaKey:
                                      ValueKey('admin-user-quota-${user.id}'),
                                  quota: _quota,
                                  enabled: !busy,
                                  quotaValidator: (v) {
                                    final amount =
                                        int.tryParse(v?.trim() ?? '') ?? 0;
                                    if (amount <= 0) {
                                      return 'Enter a limit greater than zero.';
                                    }
                                    if (v?.trim() != _initialQuota &&
                                        amount * _gib < user.storageUsed) {
                                      return 'Their memories need at least ${(user.storageUsed / _gib).ceil()} GB.';
                                    }
                                    return null;
                                  }),
                              const SizedBox(height: 18),
                              Text(
                                  '${FileSizeFormatter.compact(user.storageUsed)} currently used.',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant)),
                              const SizedBox(height: 14),
                              SwitchListTile(
                                  key: ValueKey('admin-user-active-${user.id}'),
                                  contentPadding: EdgeInsets.zero,
                                  title: const Text('Can sign in'),
                                  subtitle: const Text(
                                      'Turning access off keeps their memories in place.'),
                                  value: _active,
                                  onChanged: self || busy
                                      ? null
                                      : (v) => setState(() => _active = v)),
                              if (self) ...[
                                const SizedBox(height: 12),
                                const Text(
                                    'Another administrator manages your role and access.')
                              ],
                              if (widget.admin.actionMessageIsError &&
                                  widget.admin.actionMessage != null) ...[
                                const SizedBox(height: 16),
                                _Notice(
                                    text: widget.admin.actionMessage!,
                                    error: true)
                              ],
                            ])))),
            actions: [
              TextButton(
                  onPressed: busy ? null : () => Navigator.pop(context),
                  child: const Text('Cancel')),
              FilledButton(
                  key: ValueKey('admin-user-save-${user.id}'),
                  onPressed: busy || !dirty ? null : _save,
                  child: Text(busy ? 'Saving…' : 'Save changes')),
            ]);
      });
}
