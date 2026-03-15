import 'package:flutter/material.dart';

import '../../features/admin/providers/admin_dashboard_provider.dart';
import '../../features/admin/ui/admin_dashboard_screen.dart';
import '../../features/albums/providers/album_provider.dart';
import '../../features/albums/ui/album_list_screen.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../../features/auth/ui/login_screen.dart';
import '../../features/comments/providers/comment_provider.dart';
import '../../features/media/providers/media_list_provider.dart';
import '../../features/media/providers/media_upload_provider.dart';
import '../../features/media/ui/photo_grid_screen.dart';
import '../../features/profile/providers/profile_provider.dart';
import '../../features/profile/ui/profile_screen.dart';
import '../../shared/widgets/main_scaffold.dart';
import '../config/app_config.dart';
import '../network/api_client.dart';
import '../websocket/upload_progress_hub.dart';

enum AppSection { media, albums, profile, admin }

class AppRoutePath {
  const AppRoutePath.login()
      : section = null,
        isLogin = true;

  const AppRoutePath.section(this.section) : isLogin = false;

  final AppSection? section;
  final bool isLogin;

  Uri toUri() {
    if (isLogin) {
      return Uri(path: '/login');
    }

    return Uri(path: '/${_segmentForSection(section ?? AppSection.media)}');
  }

  static String _segmentForSection(AppSection section) {
    switch (section) {
      case AppSection.media:
        return 'media';
      case AppSection.albums:
        return 'albums';
      case AppSection.profile:
        return 'profile';
      case AppSection.admin:
        return 'admin';
    }
  }
}

class AppRouteInformationParser extends RouteInformationParser<AppRoutePath> {
  @override
  Future<AppRoutePath> parseRouteInformation(
    RouteInformation routeInformation,
  ) async {
    final uri = routeInformation.uri;
    final firstSegment = uri.pathSegments.isEmpty ? '' : uri.pathSegments.first;

    switch (firstSegment) {
      case '':
      case 'media':
        return const AppRoutePath.section(AppSection.media);
      case 'albums':
        return const AppRoutePath.section(AppSection.albums);
      case 'profile':
        return const AppRoutePath.section(AppSection.profile);
      case 'admin':
        return const AppRoutePath.section(AppSection.admin);
      case 'login':
        return const AppRoutePath.login();
      default:
        return const AppRoutePath.section(AppSection.media);
    }
  }

  @override
  RouteInformation? restoreRouteInformation(AppRoutePath configuration) {
    return RouteInformation(uri: configuration.toUri());
  }
}

class AppRouter extends RouterDelegate<AppRoutePath>
    with ChangeNotifier, PopNavigatorRouterDelegateMixin<AppRoutePath> {
  AppRouter({
    required this.appConfig,
    required this.apiClient,
    required this.authProvider,
    required this.mediaProvider,
    required this.mediaUploadProvider,
    required this.albumProvider,
    required this.commentProvider,
    required this.profileProvider,
    required this.adminProvider,
    required this.uploadProgressHub,
  }) {
    authProvider.addListener(_handleAuthChanged);
  }

  final AppConfig appConfig;
  final ApiClient apiClient;
  final AuthProvider authProvider;
  final MediaListProvider mediaProvider;
  final MediaUploadProvider mediaUploadProvider;
  final AlbumProvider albumProvider;
  final CommentProvider commentProvider;
  final ProfileProvider profileProvider;
  final AdminDashboardProvider adminProvider;
  final UploadProgressHub uploadProgressHub;

  @override
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  late final RouterConfig<AppRoutePath> routerConfig =
      RouterConfig<AppRoutePath>(
    routeInformationProvider: PlatformRouteInformationProvider(
      initialRouteInformation: RouteInformation(uri: Uri(path: '/media')),
    ),
    routeInformationParser: AppRouteInformationParser(),
    routerDelegate: this,
    backButtonDispatcher: RootBackButtonDispatcher(),
  );

  AppRoutePath _requestedPath = const AppRoutePath.section(AppSection.media);
  AppSection _selectedSection = AppSection.media;

  @override
  AppRoutePath get currentConfiguration {
    if (authProvider.status == AuthStatus.restoring) {
      return _requestedPath;
    }

    if (!authProvider.isAuthenticated) {
      return const AppRoutePath.login();
    }

    return AppRoutePath.section(_selectedSection);
  }

  @override
  Future<void> setNewRoutePath(AppRoutePath configuration) async {
    _requestedPath = configuration;
    if (!authProvider.isAuthenticated) {
      notifyListeners();
      return;
    }

    _selectedSection = _coerceSection(
      configuration.section ?? AppSection.media,
    );
    notifyListeners();
  }

  void goToSection(AppSection section) {
    _requestedPath = AppRoutePath.section(section);
    _selectedSection = _coerceSection(section);
    notifyListeners();
  }

  void _handleAuthChanged() {
    if (authProvider.isAuthenticated) {
      _selectedSection = _coerceSection(
        _requestedPath.section ?? AppSection.media,
      );
    } else {
      _selectedSection = AppSection.media;
    }
    notifyListeners();
  }

  AppSection _coerceSection(AppSection section) {
    if (section == AppSection.admin && !authProvider.canAccessAdmin) {
      return AppSection.profile;
    }
    return section;
  }

  @override
  Widget build(BuildContext context) {
    final page = authProvider.status == AuthStatus.restoring
        ? const MaterialPage<void>(
            key: ValueKey<String>('restoring'),
            child: _RestoringScreen(),
          )
        : authProvider.isAuthenticated
            ? MaterialPage<void>(
                key: ValueKey<String>('shell-${_selectedSection.name}'),
                child: MainScaffold(
                  config: appConfig,
                  authProvider: authProvider,
                  selectedSection: _selectedSection,
                  onDestinationSelected: goToSection,
                  child: _buildSectionBody(),
                ),
              )
            : MaterialPage<void>(
                key: const ValueKey<String>('login'),
                child: LoginScreen(
                  authProvider: authProvider,
                  apiClient: apiClient,
                  config: appConfig,
                ),
              );

    return Navigator(
      key: navigatorKey,
      pages: [page],
      onDidRemovePage: (Page<Object?> page) {},
    );
  }

  Widget _buildSectionBody() {
    switch (_selectedSection) {
      case AppSection.media:
        return PhotoGridScreen(
          mediaProvider: mediaProvider,
          mediaUploadProvider: mediaUploadProvider,
          commentProvider: commentProvider,
          apiClient: apiClient,
          uploadProgressHub: uploadProgressHub,
        );
      case AppSection.albums:
        return AlbumListScreen(albumProvider: albumProvider);
      case AppSection.profile:
        return ProfileScreen(profileProvider: profileProvider);
      case AppSection.admin:
        return AdminDashboardScreen(adminProvider: adminProvider);
    }
  }

  @override
  void dispose() {
    authProvider.removeListener(_handleAuthChanged);
    super.dispose();
  }
}

class _RestoringScreen extends StatelessWidget {
  const _RestoringScreen();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: <Color>[
              theme.colorScheme.primary.withValues(alpha: 0.2),
              theme.scaffoldBackgroundColor,
              theme.colorScheme.secondary.withValues(alpha: 0.18),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              SizedBox(height: 16),
              Text('Restoring your session...'),
            ],
          ),
        ),
      ),
    );
  }
}
