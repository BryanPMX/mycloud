import 'package:flutter/material.dart';
import '../../core/config/app_config.dart';
import '../../core/connectivity/connectivity_service.dart';
import '../../core/router/app_router.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../../features/directory/providers/family_directory_provider.dart';
import '../utils/file_size_formatter.dart';
import 'user_avatar.dart';
import 'vault_ui.dart';

class MainScaffold extends StatelessWidget {
  const MainScaffold(
      {super.key,
      required this.config,
      required this.authProvider,
      required this.familyDirectoryProvider,
      required this.connectivityService,
      required this.selectedSection,
      required this.onDestinationSelected,
      required this.child});
  final AppConfig config;
  final AuthProvider authProvider;
  final FamilyDirectoryProvider familyDirectoryProvider;
  final ConnectivityService connectivityService;
  final AppSection selectedSection;
  final ValueChanged<AppSection> onDestinationSelected;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: Listenable.merge([authProvider, connectivityService]),
      builder: (context, _) => LayoutBuilder(builder: (context, constraints) {
            final desktop = constraints.maxWidth >= 800;
            final wide = constraints.maxWidth >= 1200;
            final colors = Theme.of(context).colorScheme;
            final user = authProvider.currentUser;
            final destinations = <(AppSection, String, IconData)>[
              (AppSection.media, 'Vault', Icons.grid_view_rounded),
              (AppSection.feed, 'Shared', Icons.people_outline_rounded),
              (AppSection.albums, 'Collections', Icons.bookmarks_outlined),
              (AppSection.profile, 'Profile', Icons.person_outline_rounded),
              if (authProvider.canAccessAdmin)
                (AppSection.admin, 'Admin', Icons.tune_rounded),
            ];
            Widget avatar() => user == null
                ? const SizedBox.shrink()
                : UserAvatar(
                    userId: user.id,
                    displayName: user.displayName,
                    initialAvatarUrl: user.avatarUrl,
                    directoryProvider: familyDirectoryProvider,
                    radius: 17);
            return Scaffold(
              bottomNavigationBar: desktop
                  ? null
                  : DecoratedBox(
                      decoration: BoxDecoration(
                          color: colors.surface,
                          border: Border(
                              top: BorderSide(color: colors.outlineVariant))),
                      child: SafeArea(
                          top: false,
                          child: Padding(
                              padding: const EdgeInsets.fromLTRB(8, 5, 8, 5),
                              child: Row(
                                  children: destinations
                                      .map((d) => Expanded(
                                          child: _NavItem(
                                              label: d.$2,
                                              icon: d.$3,
                                              selected: selectedSection == d.$1,
                                              compact: true,
                                              onTap: () =>
                                                  onDestinationSelected(d.$1))))
                                      .toList())))),
              body: SafeArea(
                  bottom: false,
                  child: Row(children: [
                    if (desktop)
                      Container(
                          width: wide ? 222 : 88,
                          decoration: BoxDecoration(
                              color: colors.surface,
                              border: Border(
                                  right: BorderSide(
                                      color: colors.outlineVariant))),
                          padding: EdgeInsets.symmetric(
                              horizontal: wide ? 24 : 12, vertical: 30),
                          child: Column(
                              crossAxisAlignment: wide
                                  ? CrossAxisAlignment.start
                                  : CrossAxisAlignment.center,
                              children: [
                                VaultLogo(compact: !wide),
                                if (wide) ...[
                                  const SizedBox(height: 13),
                                  const VaultEyebrow('A little more yours')
                                ],
                                const SizedBox(height: 45),
                                for (final d in destinations)
                                  Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: _NavItem(
                                          label: d.$2,
                                          icon: d.$3,
                                          selected: selectedSection == d.$1,
                                          compact: !wide,
                                          onTap: () =>
                                              onDestinationSelected(d.$1))),
                                const Spacer(),
                                if (wide && user != null) ...[
                                  Row(children: [
                                    Icon(Icons.lock_outline_rounded,
                                        size: 15,
                                        color: colors.onSurfaceVariant),
                                    const SizedBox(width: 7),
                                    Expanded(
                                        child: Text('Your private space',
                                            maxLines: 2,
                                            style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                                color:
                                                    colors.onSurfaceVariant)))
                                  ]),
                                  const SizedBox(height: 14),
                                  ClipRRect(
                                      borderRadius: BorderRadius.circular(5),
                                      child: LinearProgressIndicator(
                                          value: user.storagePct.clamp(0, 1),
                                          backgroundColor:
                                              colors.surfaceContainerHighest,
                                          color: colors.primary)),
                                  const SizedBox(height: 9),
                                  Text(
                                      '${FileSizeFormatter.compact(user.storageUsed)} of ${FileSizeFormatter.compact(user.quotaBytes)}',
                                      style: TextStyle(
                                          fontSize: 10,
                                          color: colors.onSurfaceVariant)),
                                  const SizedBox(height: 26),
                                ],
                                Row(
                                    mainAxisAlignment: wide
                                        ? MainAxisAlignment.start
                                        : MainAxisAlignment.center,
                                    children: [
                                      avatar(),
                                      if (wide) ...[
                                        const SizedBox(width: 10),
                                        Expanded(
                                            child: Text(user?.displayName ?? '',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                    fontSize: 11,
                                                    fontWeight:
                                                        FontWeight.w700)))
                                      ]
                                    ]),
                                const SizedBox(height: 12),
                                TextButton.icon(
                                    onPressed: authProvider.signOut,
                                    icon: const Icon(Icons.logout_rounded,
                                        size: 17),
                                    label: Text(wide ? 'Sign out' : '',
                                        style: const TextStyle(fontSize: 11))),
                              ])),
                    Expanded(
                        child: Column(children: [
                      Container(
                          height: desktop ? 78 : 66,
                          padding: EdgeInsets.symmetric(
                              horizontal: desktop ? 36 : 20),
                          decoration: BoxDecoration(
                              border: Border(
                                  bottom: BorderSide(
                                      color: colors.outlineVariant))),
                          child: Row(children: [
                            if (!desktop)
                              const VaultLogo(size: 30)
                            else ...[
                              const VaultEyebrow('Your space'),
                              Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12),
                                  child: Text('/',
                                      style: TextStyle(color: colors.outline))),
                              Text(
                                  destinations
                                      .firstWhere(
                                          (d) => d.$1 == selectedSection)
                                      .$2,
                                  style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700))
                            ],
                            const Spacer(),
                            if (desktop) ...[
                              Icon(Icons.lock_outline_rounded,
                                  size: 14, color: colors.onSurfaceVariant),
                              const SizedBox(width: 7),
                              Text(
                                  config.useDemoData
                                      ? 'Sample vault'
                                      : 'Private by default',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: colors.onSurfaceVariant)),
                              const SizedBox(width: 24)
                            ],
                            IconButton(
                                tooltip: 'Your profile',
                                onPressed: () =>
                                    onDestinationSelected(AppSection.profile),
                                icon: avatar()),
                            if (!desktop)
                              PopupMenuButton<String>(
                                  tooltip: 'Account options',
                                  onSelected: (_) => authProvider.signOut(),
                                  itemBuilder: (_) => const [
                                        PopupMenuItem(
                                            value: 'logout',
                                            child: Text('Sign out'))
                                      ]),
                          ])),
                      if (connectivityService.isOffline)
                        Material(
                            color: colors.primaryContainer,
                            child: Padding(
                                padding: const EdgeInsets.all(10),
                                child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: const [
                                      Icon(Icons.wifi_off_rounded, size: 15),
                                      SizedBox(width: 8),
                                      Flexible(
                                          child: Text(
                                              'You’re offline. We’ll reconnect when you’re back.',
                                              style: TextStyle(fontSize: 11)))
                                    ]))),
                      Expanded(
                          child: Padding(
                              padding: EdgeInsets.fromLTRB(desktop ? 36 : 18,
                                  desktop ? 30 : 22, desktop ? 36 : 18, 0),
                              child: AnimatedSwitcher(
                                  duration:
                                      MediaQuery.disableAnimationsOf(context)
                                          ? Duration.zero
                                          : const Duration(milliseconds: 180),
                                  transitionBuilder: (child, animation) =>
                                      FadeTransition(
                                          opacity: animation, child: child),
                                  child: child))),
                    ])),
                  ])),
            );
          }));
}

class _NavItem extends StatelessWidget {
  const _NavItem(
      {required this.label,
      required this.icon,
      required this.selected,
      required this.compact,
      required this.onTap});
  final String label;
  final IconData icon;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = selected ? colors.primary : colors.onSurfaceVariant;
    return Semantics(
        excludeSemantics: true,
        onTap: onTap,
        selected: selected,
        button: true,
        label: label,
        child: Tooltip(
            message: label,
            child: Material(
                color: selected && !compact
                    ? colors.primaryContainer
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                    onTap: onTap,
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                        constraints: const BoxConstraints(minHeight: 52),
                        padding: EdgeInsets.symmetric(
                            horizontal: compact ? 3 : 15, vertical: 8),
                        child: compact
                            ? Column(mainAxisSize: MainAxisSize.min, children: [
                                Icon(icon, size: 23, color: color),
                                const SizedBox(height: 5),
                                Text(label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: selected
                                            ? FontWeight.w800
                                            : FontWeight.w500,
                                        color: color))
                              ])
                            : Row(children: [
                                Icon(icon, size: 21, color: color),
                                const SizedBox(width: 13),
                                Expanded(
                                    child: Text(label,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: selected
                                                ? FontWeight.w800
                                                : FontWeight.w600,
                                            color: color)))
                              ]))))));
  }
}
