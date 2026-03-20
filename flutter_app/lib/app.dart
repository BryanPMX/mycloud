import 'dart:async';

import 'package:flutter/material.dart';

import 'core/config/app_config.dart';
import 'core/connectivity/connectivity_service.dart';
import 'core/network/api_client.dart';
import 'core/network/api_transport.dart';
import 'core/router/app_router.dart';
import 'core/storage/secure_storage.dart';
import 'core/theme/app_theme.dart';
import 'core/websocket/upload_progress_hub.dart';
import 'features/admin/providers/admin_dashboard_provider.dart';
import 'features/albums/providers/album_provider.dart';
import 'features/auth/providers/auth_provider.dart';
import 'features/comments/providers/comment_provider.dart';
import 'features/directory/providers/family_directory_provider.dart';
import 'features/media/data/upload_picker.dart';
import 'features/media/providers/media_list_provider.dart';
import 'features/media/providers/media_upload_provider.dart';
import 'features/profile/data/avatar_picker.dart';
import 'features/profile/providers/profile_provider.dart';

class App extends StatefulWidget {
  const App({
    super.key,
    required this.config,
    this.controller,
    this.uploadFilesPicker,
    this.lostUploadFilesRetriever,
    this.avatarFilePicker,
    this.lostAvatarFileRetriever,
  });

  final AppConfig config;
  final AppController? controller;
  final UploadFilesPicker? uploadFilesPicker;
  final LostUploadFilesRetriever? lostUploadFilesRetriever;
  final AvatarFilePicker? avatarFilePicker;
  final LostAvatarFileRetriever? lostAvatarFileRetriever;

  @override
  State<App> createState() => _AppState();
}

class AppController {
  AuthProvider? get authProvider => _authProvider;
  MediaUploadProvider? get mediaUploadProvider => _mediaUploadProvider;
  UploadProgressHub? get uploadProgressHub => _uploadProgressHub;

  AuthProvider? _authProvider;
  MediaUploadProvider? _mediaUploadProvider;
  UploadProgressHub? _uploadProgressHub;

  void _attach({
    required AuthProvider authProvider,
    required MediaUploadProvider mediaUploadProvider,
    required UploadProgressHub uploadProgressHub,
  }) {
    _authProvider = authProvider;
    _mediaUploadProvider = mediaUploadProvider;
    _uploadProgressHub = uploadProgressHub;
  }
}

class _AppState extends State<App> {
  late final ConnectivityService _connectivityService;
  late final ApiTransport _transport;
  late final ApiClient _apiClient;
  late final SecureStorage _secureStorage;
  late final AuthProvider _authProvider;
  late final MediaListProvider _mediaProvider;
  late final MediaUploadProvider _mediaUploadProvider;
  late final AlbumProvider _albumProvider;
  late final CommentProvider _commentProvider;
  late final AdminDashboardProvider _adminProvider;
  late final FamilyDirectoryProvider _familyDirectoryProvider;
  late final ProfileProvider _profileProvider;
  late final UploadProgressHub _uploadProgressHub;
  late final AppRouter _router;

  String? _bootstrappedUserId;
  String? _observedMediaId;

  @override
  void initState() {
    super.initState();
    _connectivityService = ConnectivityService();
    _transport = ApiTransport(
      onReachable: _connectivityService.markReachable,
      onUnreachable: _connectivityService.markUnreachable,
    );
    _apiClient = ApiClient(widget.config);
    _secureStorage = SecureStorage();
    _authProvider = AuthProvider(
      config: widget.config,
      apiClient: _apiClient,
      transport: _transport,
      secureStorage: _secureStorage,
    );
    _mediaProvider = MediaListProvider(
      config: widget.config,
      apiClient: _apiClient,
      transport: _transport,
      authProvider: _authProvider,
      connectivityService: _connectivityService,
    );
    _mediaUploadProvider = MediaUploadProvider(
      config: widget.config,
      apiClient: _apiClient,
      transport: _transport,
      authProvider: _authProvider,
      mediaProvider: _mediaProvider,
      connectivityService: _connectivityService,
      uploadFilesPicker: widget.uploadFilesPicker,
      lostUploadFilesRetriever: widget.lostUploadFilesRetriever,
    );
    _albumProvider = AlbumProvider(
      config: widget.config,
      apiClient: _apiClient,
      transport: _transport,
      authProvider: _authProvider,
      connectivityService: _connectivityService,
    );
    _commentProvider = CommentProvider(
      config: widget.config,
      apiClient: _apiClient,
      transport: _transport,
      authProvider: _authProvider,
      connectivityService: _connectivityService,
    );
    _adminProvider = AdminDashboardProvider(
      config: widget.config,
      apiClient: _apiClient,
      transport: _transport,
      authProvider: _authProvider,
    );
    _familyDirectoryProvider = FamilyDirectoryProvider(
      config: widget.config,
      apiClient: _apiClient,
      transport: _transport,
      authProvider: _authProvider,
    );
    _profileProvider = ProfileProvider(
      config: widget.config,
      apiClient: _apiClient,
      transport: _transport,
      authProvider: _authProvider,
      adminProvider: _adminProvider,
      connectivityService: _connectivityService,
      avatarFilePicker: widget.avatarFilePicker,
      lostAvatarFileRetriever: widget.lostAvatarFileRetriever,
    );
    _uploadProgressHub = UploadProgressHub(
      config: widget.config,
      authProvider: _authProvider,
      mediaProvider: _mediaProvider,
      uploadProvider: _mediaUploadProvider,
    );
    widget.controller?._attach(
      authProvider: _authProvider,
      mediaUploadProvider: _mediaUploadProvider,
      uploadProgressHub: _uploadProgressHub,
    );
    _router = AppRouter(
      appConfig: widget.config,
      apiClient: _apiClient,
      authProvider: _authProvider,
      mediaProvider: _mediaProvider,
      mediaUploadProvider: _mediaUploadProvider,
      albumProvider: _albumProvider,
      commentProvider: _commentProvider,
      profileProvider: _profileProvider,
      adminProvider: _adminProvider,
      familyDirectoryProvider: _familyDirectoryProvider,
      uploadProgressHub: _uploadProgressHub,
      connectivityService: _connectivityService,
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
    _uploadProgressHub.dispose();
    _profileProvider.dispose();
    _familyDirectoryProvider.dispose();
    _adminProvider.dispose();
    _commentProvider.dispose();
    _albumProvider.dispose();
    _mediaUploadProvider.dispose();
    _mediaProvider.dispose();
    _authProvider.dispose();
    _transport.dispose();
    _connectivityService.dispose();
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
      _mediaUploadProvider.reset();
      _mediaProvider.reset();
      _albumProvider.reset();
      _commentProvider.clear();
      _adminProvider.reset();
      _familyDirectoryProvider.reset();
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

    await Future.wait<void>(<Future<void>>[
      _albumProvider.load(),
      _familyDirectoryProvider.load(),
    ]);
    if (_authProvider.currentUser?.id != userId) {
      return;
    }

    await Future.wait<void>(<Future<void>>[
      _mediaUploadProvider.recoverLostFiles(),
      _profileProvider.recoverLostAvatarUpload(),
    ]);
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
