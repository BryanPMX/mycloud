import 'package:flutter/material.dart';

import 'core/config/app_config.dart';
import 'core/network/api_client.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/admin/providers/admin_dashboard_provider.dart';
import 'features/albums/providers/album_provider.dart';
import 'features/auth/providers/auth_provider.dart';
import 'features/comments/providers/comment_provider.dart';
import 'features/media/providers/media_list_provider.dart';
import 'features/profile/providers/profile_provider.dart';

class App extends StatefulWidget {
  const App({super.key, required this.config});

  final AppConfig config;

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  late final ApiClient _apiClient;
  late final AuthProvider _authProvider;
  late final MediaListProvider _mediaProvider;
  late final AlbumProvider _albumProvider;
  late final CommentProvider _commentProvider;
  late final AdminDashboardProvider _adminProvider;
  late final ProfileProvider _profileProvider;
  late final AppRouter _router;

  @override
  void initState() {
    super.initState();
    _apiClient = ApiClient(widget.config);
    _authProvider = AuthProvider(config: widget.config);
    _mediaProvider = MediaListProvider();
    _albumProvider = AlbumProvider();
    _commentProvider = CommentProvider();
    _adminProvider = AdminDashboardProvider();
    _profileProvider = ProfileProvider(
      config: widget.config,
      apiClient: _apiClient,
      authProvider: _authProvider,
      adminProvider: _adminProvider,
    );
    _router = AppRouter(
      appConfig: widget.config,
      apiClient: _apiClient,
      authProvider: _authProvider,
      mediaProvider: _mediaProvider,
      albumProvider: _albumProvider,
      commentProvider: _commentProvider,
      profileProvider: _profileProvider,
      adminProvider: _adminProvider,
    );
    _authProvider.restore();
  }

  @override
  void dispose() {
    _router.dispose();
    _profileProvider.dispose();
    _adminProvider.dispose();
    _commentProvider.dispose();
    _albumProvider.dispose();
    _mediaProvider.dispose();
    _authProvider.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: widget.config.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      restorationScopeId: 'mycloud',
      routerConfig: _router.routerConfig,
    );
  }
}
