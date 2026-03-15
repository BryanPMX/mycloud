import 'package:flutter/material.dart';

import '../../core/config/app_config.dart';
import '../../core/connectivity/connectivity_service.dart';
import '../../core/router/app_router.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../../features/directory/providers/family_directory_provider.dart';
import 'user_avatar.dart';

class MainScaffold extends StatelessWidget {
  const MainScaffold({
    super.key,
    required this.config,
    required this.authProvider,
    required this.familyDirectoryProvider,
    required this.connectivityService,
    required this.selectedSection,
    required this.onDestinationSelected,
    required this.child,
  });

  final AppConfig config;
  final AuthProvider authProvider;
  final FamilyDirectoryProvider familyDirectoryProvider;
  final ConnectivityService connectivityService;
  final AppSection selectedSection;
  final ValueChanged<AppSection> onDestinationSelected;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final gradient = LinearGradient(
      colors: <Color>[
        theme.colorScheme.primary.withValues(alpha: 0.18),
        theme.scaffoldBackgroundColor,
        theme.colorScheme.secondary.withValues(alpha: 0.18),
      ],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );

    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[
        authProvider,
        connectivityService,
      ]),
      builder: (context, _) {
        final destinations = _destinations(authProvider.canAccessAdmin);
        final selectedIndex = destinations.indexWhere(
          (destination) => destination.section == selectedSection,
        );
        final user = authProvider.currentUser;

        return DecoratedBox(
          decoration: BoxDecoration(gradient: gradient),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final useRail = constraints.maxWidth >= 600;
              return Scaffold(
                backgroundColor: Colors.transparent,
                bottomNavigationBar: useRail
                    ? null
                    : SafeArea(
                        top: false,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          child: NavigationBar(
                            selectedIndex:
                                selectedIndex < 0 ? 0 : selectedIndex,
                            destinations: destinations
                                .map(
                                  (destination) => NavigationDestination(
                                    icon: Icon(destination.icon),
                                    selectedIcon: Icon(
                                      destination.selectedIcon,
                                    ),
                                    label: destination.label,
                                  ),
                                )
                                .toList(growable: false),
                            onDestinationSelected: (index) {
                              onDestinationSelected(
                                destinations[index].section,
                              );
                            },
                          ),
                        ),
                      ),
                body: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: useRail
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Card(
                                child: SizedBox(
                                  width: 104,
                                  child: Column(
                                    children: [
                                      const SizedBox(height: 16),
                                      CircleAvatar(
                                        radius: 28,
                                        backgroundColor: theme
                                            .colorScheme.secondaryContainer,
                                        child: Text(
                                          config.appName.substring(0, 1),
                                          style: theme.textTheme.titleLarge,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        config.appName,
                                        style: theme.textTheme.titleMedium,
                                      ),
                                      const SizedBox(height: 8),
                                      Chip(
                                        label: Text(config.environmentLabel),
                                      ),
                                      const SizedBox(height: 8),
                                      Expanded(
                                        child: NavigationRail(
                                          selectedIndex: selectedIndex < 0
                                              ? 0
                                              : selectedIndex,
                                          labelType:
                                              NavigationRailLabelType.all,
                                          groupAlignment: -0.8,
                                          useIndicator: true,
                                          destinations: destinations
                                              .map(
                                                (
                                                  destination,
                                                ) =>
                                                    NavigationRailDestination(
                                                  icon: Icon(destination.icon),
                                                  selectedIcon: Icon(
                                                    destination.selectedIcon,
                                                  ),
                                                  label: Text(
                                                    destination.label,
                                                  ),
                                                ),
                                              )
                                              .toList(growable: false),
                                          onDestinationSelected: (index) {
                                            onDestinationSelected(
                                              destinations[index].section,
                                            );
                                          },
                                        ),
                                      ),
                                      if (user != null) ...[
                                        _UserBadge(
                                          userId: user.id,
                                          displayName: user.displayName,
                                          avatarUrl: user.avatarUrl,
                                          familyDirectoryProvider:
                                              familyDirectoryProvider,
                                        ),
                                        const SizedBox(height: 12),
                                        IconButton.filledTonal(
                                          onPressed: () {
                                            authProvider.signOut();
                                          },
                                          icon: const Icon(
                                            Icons.logout_rounded,
                                          ),
                                        ),
                                        const SizedBox(height: 16),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: _MainPanel(
                                  config: config,
                                  authProvider: authProvider,
                                  connectivityService: connectivityService,
                                  selectedSection: selectedSection,
                                  child: child,
                                ),
                              ),
                            ],
                          )
                        : _MainPanel(
                            config: config,
                            authProvider: authProvider,
                            connectivityService: connectivityService,
                            selectedSection: selectedSection,
                            child: child,
                          ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  List<_DestinationSpec> _destinations(bool includeAdmin) {
    return [
      const _DestinationSpec(
        section: AppSection.media,
        label: 'Library',
        icon: Icons.photo_library_outlined,
        selectedIcon: Icons.photo_library_rounded,
      ),
      const _DestinationSpec(
        section: AppSection.albums,
        label: 'Albums',
        icon: Icons.collections_bookmark_outlined,
        selectedIcon: Icons.collections_bookmark_rounded,
      ),
      const _DestinationSpec(
        section: AppSection.profile,
        label: 'Profile',
        icon: Icons.person_outline_rounded,
        selectedIcon: Icons.person_rounded,
      ),
      if (includeAdmin)
        const _DestinationSpec(
          section: AppSection.admin,
          label: 'Admin',
          icon: Icons.space_dashboard_outlined,
          selectedIcon: Icons.space_dashboard_rounded,
        ),
    ];
  }
}

class _MainPanel extends StatelessWidget {
  const _MainPanel({
    required this.config,
    required this.authProvider,
    required this.connectivityService,
    required this.selectedSection,
    required this.child,
  });

  final AppConfig config;
  final AuthProvider authProvider;
  final ConnectivityService connectivityService;
  final AppSection selectedSection;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = authProvider.currentUser;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 16,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _titleForSection(selectedSection),
                      style: theme.textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _subtitleForSection(selectedSection),
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                Chip(
                  avatar: const Icon(Icons.cloud_done_rounded, size: 18),
                  label: Text(config.apiBaseUri.host),
                ),
                Chip(
                  avatar: Icon(
                    switch (connectivityService.status) {
                      ConnectivityStatus.online => Icons.wifi_rounded,
                      ConnectivityStatus.offline =>
                        Icons.portable_wifi_off_rounded,
                      ConnectivityStatus.unknown => Icons.sync_rounded,
                    },
                    size: 18,
                  ),
                  label: Text('Network ${connectivityService.statusLabel}'),
                ),
                if (user != null && !authProvider.canAccessAdmin)
                  Chip(
                    avatar: const Icon(Icons.shield_outlined, size: 18),
                    label: Text(user.role.label),
                  ),
                if (user != null)
                  FilledButton.tonalIcon(
                    onPressed: () {
                      authProvider.signOut();
                    },
                    icon: const Icon(Icons.logout_rounded),
                    label: const Text('Sign out'),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 240),
                child: child,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _titleForSection(AppSection section) {
    switch (section) {
      case AppSection.media:
        return 'Media library';
      case AppSection.albums:
        return 'Album workspace';
      case AppSection.profile:
        return 'Profile and rollout';
      case AppSection.admin:
        return 'Admin overview';
    }
  }

  String _subtitleForSection(AppSection section) {
    switch (section) {
      case AppSection.media:
        return 'Live media reads, multipart uploads, worker progress, favorites, comment mutations, and presigned thumbnail fetches.';
      case AppSection.albums:
        return 'Owned and shared album lists, album membership dialogs, and album sharing controls now read and write against the live backend.';
      case AppSection.profile:
        return 'Deployment endpoints, storage posture, live profile writes, and secure native token restore now reflect the current rollout state.';
      case AppSection.admin:
        return 'Recent backend delivery, live system stats, invites, and account-management controls for the current admin slice.';
    }
  }
}

class _DestinationSpec {
  const _DestinationSpec({
    required this.section,
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final AppSection section;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

class _UserBadge extends StatelessWidget {
  const _UserBadge({
    required this.userId,
    required this.displayName,
    required this.familyDirectoryProvider,
    this.avatarUrl,
  });

  final String userId;
  final String displayName;
  final String? avatarUrl;
  final FamilyDirectoryProvider familyDirectoryProvider;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        UserAvatar(
          userId: userId,
          displayName: displayName,
          initialAvatarUrl: avatarUrl,
          directoryProvider: familyDirectoryProvider,
        ),
        const SizedBox(height: 8),
        Text(
          displayName,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }
}
