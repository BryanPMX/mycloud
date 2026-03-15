import 'package:flutter/foundation.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/api_transport.dart';
import '../../auth/providers/auth_provider.dart';
import '../domain/directory_user.dart';

class FamilyDirectoryProvider extends ChangeNotifier {
  FamilyDirectoryProvider({
    required AppConfig config,
    required ApiClient apiClient,
    required ApiTransport transport,
    required AuthProvider authProvider,
    Duration defaultAvatarTtl = const Duration(minutes: 5),
    Duration avatarRefreshLeeway = const Duration(seconds: 30),
  })  : _config = config,
        _apiClient = apiClient,
        _transport = transport,
        _authProvider = authProvider,
        _defaultAvatarTtl = defaultAvatarTtl,
        _avatarRefreshLeeway = avatarRefreshLeeway {
    _authProvider.addListener(_handleAuthChanged);
    if (_config.useDemoData) {
      _applyDirectoryUsers(_seedUsers);
      _hasLoaded = true;
    }
    _handleAuthChanged();
  }

  static final List<DirectoryUser> _seedUsers = <DirectoryUser>[
    const DirectoryUser(
      id: 'user-admin',
      displayName: 'Admin Operator',
    ),
    const DirectoryUser(
      id: 'user-member',
      displayName: 'Family Member',
    ),
  ];

  final AppConfig _config;
  final ApiClient _apiClient;
  final ApiTransport _transport;
  final AuthProvider _authProvider;
  final Duration _defaultAvatarTtl;
  final Duration _avatarRefreshLeeway;

  final List<DirectoryUser> _users = <DirectoryUser>[];
  final Map<String, _AvatarCacheEntry> _avatarCache =
      <String, _AvatarCacheEntry>{};
  final Set<String> _refreshingAvatarUserIds = <String>{};

  bool _isLoading = false;
  bool _hasLoaded = false;
  String? _errorMessage;

  List<DirectoryUser> get users => List<DirectoryUser>.unmodifiable(_users);

  bool get isLoading => _isLoading;

  bool get hasLoaded => _hasLoaded;

  String? get errorMessage => _errorMessage;

  String? avatarUrlFor(String userId) {
    return _avatarCache[userId.trim()]?.url;
  }

  bool avatarNeedsRefresh(String userId) {
    final normalizedUserId = userId.trim();
    if (normalizedUserId.isEmpty ||
        _refreshingAvatarUserIds.contains(normalizedUserId)) {
      return false;
    }

    final entry = _avatarCache[normalizedUserId];
    if (entry == null) {
      return true;
    }

    return DateTime.now()
        .toUtc()
        .isAfter(entry.expiresAt.subtract(_avatarRefreshLeeway));
  }

  Future<void> load() async {
    if (_config.useDemoData) {
      _applyDirectoryUsers(_seedUsers);
      _hasLoaded = true;
      _errorMessage = null;
      notifyListeners();
      return;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final response = await _authProvider.withAuthorization(
        (headers) =>
            _transport.get(_apiClient.usersDirectoryUri(), headers: headers),
      );
      final payload = response.asMap();
      final users = (payload['users'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(DirectoryUser.fromJson)
          .toList(growable: false);

      _applyDirectoryUsers(users);
      _hasLoaded = true;
    } on ApiException catch (error) {
      _errorMessage = error.message;
    } catch (_) {
      _errorMessage = 'Unable to load the family directory right now.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> ensureAvatar({
    required String userId,
    String? initialAvatarUrl,
  }) async {
    final normalizedUserId = userId.trim();
    if (normalizedUserId.isEmpty) {
      return;
    }

    if (_normalizeUrl(initialAvatarUrl) != null) {
      _rememberAvatarUrl(
        normalizedUserId,
        initialAvatarUrl,
        expiresAt: DateTime.now().toUtc().add(_defaultAvatarTtl),
      );
    }

    if (!avatarNeedsRefresh(normalizedUserId)) {
      return;
    }

    await refreshAvatar(normalizedUserId);
  }

  Future<void> refreshAvatar(String userId, {bool force = false}) async {
    final normalizedUserId = userId.trim();
    if (normalizedUserId.isEmpty ||
        _refreshingAvatarUserIds.contains(normalizedUserId)) {
      return;
    }
    if (!_config.useDemoData &&
        (_authProvider.currentUser == null ||
            (!force && !avatarNeedsRefresh(normalizedUserId)))) {
      return;
    }
    if (_config.useDemoData) {
      return;
    }

    _refreshingAvatarUserIds.add(normalizedUserId);
    try {
      final response = await _authProvider.withAuthorization(
        (headers) => _transport.get(
          _apiClient.userAvatarUri(normalizedUserId),
          headers: headers,
        ),
      );
      final payload = response.asMap();
      final url = payload['url'] as String?;
      final expiresAt =
          DateTime.tryParse(payload['expires_at'] as String? ?? '')?.toUtc();

      _rememberAvatarUrl(
        normalizedUserId,
        url,
        expiresAt: expiresAt ?? DateTime.now().toUtc().add(_defaultAvatarTtl),
        notify: true,
      );
    } on ApiException catch (error) {
      if (error.statusCode == 404) {
        _rememberAvatarUrl(
          normalizedUserId,
          null,
          expiresAt: DateTime.now().toUtc().add(_defaultAvatarTtl),
          notify: true,
        );
      }
    } catch (_) {
      // Keep the last known avatar URL on transient failures.
    } finally {
      _refreshingAvatarUserIds.remove(normalizedUserId);
    }
  }

  Future<void> handleAvatarLoadError(String userId) async {
    if (_config.useDemoData) {
      _rememberAvatarUrl(
        userId,
        null,
        expiresAt: DateTime.now().toUtc().add(_defaultAvatarTtl),
        notify: true,
      );
      return;
    }

    await refreshAvatar(userId, force: true);
  }

  void reset() {
    _users.clear();
    _avatarCache.clear();
    _refreshingAvatarUserIds.clear();
    _isLoading = false;
    _hasLoaded = false;
    _errorMessage = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _authProvider.removeListener(_handleAuthChanged);
    super.dispose();
  }

  void _handleAuthChanged() {
    final currentUser = _authProvider.currentUser;
    if (currentUser == null) {
      if (_users.isEmpty &&
          _avatarCache.isEmpty &&
          !_isLoading &&
          !_hasLoaded &&
          _errorMessage == null) {
        return;
      }
      reset();
      return;
    }

    _upsertUser(
      DirectoryUser(
        id: currentUser.id,
        displayName: currentUser.displayName,
        avatarUrl: currentUser.avatarUrl,
      ),
    );
    _rememberAvatarUrl(
      currentUser.id,
      currentUser.avatarUrl,
      expiresAt: DateTime.now().toUtc().add(_defaultAvatarTtl),
    );
    notifyListeners();
  }

  void _applyDirectoryUsers(List<DirectoryUser> users) {
    _users
      ..clear()
      ..addAll(users);

    final seededExpiry = DateTime.now().toUtc().add(_defaultAvatarTtl);
    for (final user in users) {
      _rememberAvatarUrl(user.id, user.avatarUrl, expiresAt: seededExpiry);
    }
  }

  void _upsertUser(DirectoryUser user) {
    final index = _users.indexWhere((existing) => existing.id == user.id);
    if (index == -1) {
      _users.add(user);
      return;
    }

    _users[index] = _users[index].copyWith(
      displayName: user.displayName,
      avatarUrl: user.avatarUrl,
      replaceAvatarUrl: true,
    );
  }

  void _rememberAvatarUrl(
    String userId,
    String? avatarUrl, {
    required DateTime expiresAt,
    bool notify = false,
  }) {
    final normalizedUserId = userId.trim();
    if (normalizedUserId.isEmpty) {
      return;
    }

    final normalizedUrl = _normalizeUrl(avatarUrl);
    final nextEntry = _AvatarCacheEntry(
      url: normalizedUrl,
      expiresAt: expiresAt.toUtc(),
    );
    final previousEntry = _avatarCache[normalizedUserId];
    if (previousEntry == nextEntry) {
      return;
    }

    _avatarCache[normalizedUserId] = nextEntry;
    if (notify) {
      notifyListeners();
    }
  }

  String? _normalizeUrl(String? avatarUrl) {
    final normalized = avatarUrl?.trim();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }

    return normalized;
  }
}

class _AvatarCacheEntry {
  const _AvatarCacheEntry({
    required this.url,
    required this.expiresAt,
  });

  final String? url;
  final DateTime expiresAt;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }

    return other is _AvatarCacheEntry &&
        other.url == url &&
        other.expiresAt == expiresAt;
  }

  @override
  int get hashCode => Object.hash(url, expiresAt);
}
