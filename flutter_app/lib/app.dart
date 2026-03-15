import 'dart:async';

import 'package:flutter/material.dart';

import 'core/config/app_config.dart';
import 'core/network/api_client.dart';
import 'core/network/api_transport.dart';
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
  late final ApiTransport _transport;
  late final ApiClient _apiClient;
  late final AuthProvider _authProvider;
  late final MediaListProvider _mediaProvider;
  late final AlbumProvider _albumProvider;
  late final CommentProvider _commentProvider;
  late final AdminDashboardProvider _adminProvider;
  late final ProfileProvider _profileProvider;
  late final AppRouter _router;

  String? _bootstrappedUserId;
  String? _observedMediaId;

  @override
  void initState() {
    super.initState();
    _transport = ApiTransport();
    _apiClient = ApiClient(widget.config);
    _authProvider = AuthProvider(
      config: widget.config,
      apiClient: _apiClient,
      transport: _transport,
    );
    _mediaProvider = MediaListProvider(
      config: widget.config,
      apiClient: _apiClient,
      transport: _transport,
      authProvider: _authProvider,
    );
    _albumProvider = AlbumProvider(
      config: widget.config,
      apiClient: _apiClient,
      transport: _transport,
      authProvider: _authProvider,
    );
    _commentProvider = CommentProvider(
      config: widget.config,
      apiClient: _apiClient,
      transport: _transport,
      authProvider: _authProvider,
    );
    _adminProvider = AdminDashboardProvider(
      config: widget.config,
      apiClient: _apiClient,
      transport: _transport,
      authProvider: _authProvider,
    );
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
    _authProvider.addListener(_handleAuthChanged);
    _mediaProvider.addListener(_handleSelectedMediaChanged);
    unawaited(_authProvider.restore());
  }

  @override
  void dispose() {
    _mediaProvider.removeListener(_handleSelectedMediaChanged);
    _authProvider.removeListener(_handleAuthChanged);
    _router.dispose();
    _profileProvider.dispose();
    _adminProvider.dispose();
    _commentProvider.dispose();
    _albumProvider.dispose();
    _mediaProvider.dispose();
    _authProvider.dispose();
    _transport.dispose();
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

  void _handleAuthChanged() {
    final user = _authProvider.currentUser;
    if (user == null) {
      _bootstrappedUserId = null;
      _observedMediaId = null;
      _mediaProvider.reset();
      _albumProvider.reset();
      _commentProvider.clear();
      _adminProvider.reset();
      return;
    }

    if (_bootstrappedUserId == user.id) {
      if (!_authProvider.canAccessAdmin) {
        _adminProvider.reset();
      }
      return;
    }

    _bootstrappedUserId = user.id;
    unawaited(_bootstrapAuthenticatedState(user.id));
  }

  Future<void> _bootstrapAuthenticatedState(String userId) async {
    await _mediaProvider.load();
    if (_authProvider.currentUser?.id != userId) {
      return;
    }

    await _albumProvider.load();
    if (_authProvider.currentUser?.id != userId) {
      return;
    }

    if (_authProvider.canAccessAdmin) {
      await _adminProvider.load();
      if (_authProvider.currentUser?.id != userId) {
        return;
      }
    } else {
      _adminProvider.reset();
    }

    final selectedMediaId = _mediaProvider.selectedMedia?.id;
    _observedMediaId = selectedMediaId;
    if (selectedMediaId == null) {
      _commentProvider.clear();
      return;
    }

    await _commentProvider.loadForMedia(selectedMediaId);
  }

  void _handleSelectedMediaChanged() {
    if (!_authProvider.isAuthenticated) {
      return;
    }

    final selectedMediaId = _mediaProvider.selectedMedia?.id;
    if (selectedMediaId == _observedMediaId) {
      return;
    }

    _observedMediaId = selectedMediaId;
    if (selectedMediaId == null) {
      _commentProvider.clear();
      return;
    }

    unawaited(_commentProvider.loadForMedia(selectedMediaId));
  }
}
