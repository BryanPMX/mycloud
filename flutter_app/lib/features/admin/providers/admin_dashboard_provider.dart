import 'package:flutter/foundation.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/api_transport.dart';
import '../../auth/domain/user.dart';
import '../../auth/providers/auth_provider.dart';
import '../domain/admin_invite_result.dart';
import '../domain/admin_stats.dart';
import '../domain/admin_user.dart';

class AdminDashboardProvider extends ChangeNotifier {
  AdminDashboardProvider({
    required AppConfig config,
    required ApiClient apiClient,
    required ApiTransport transport,
    required AuthProvider authProvider,
  })  : _config = config,
        _apiClient = apiClient,
        _transport = transport,
        _authProvider = authProvider,
        _users = List<AdminUser>.of(
          config.useDemoData ? _seedUsers : const <AdminUser>[],
        );

  final AppConfig _config;
  final ApiClient _apiClient;
  final ApiTransport _transport;
  final AuthProvider _authProvider;

  static const AdminStats _seedStats = AdminStats(
    totalUsers: 52,
    activeUsers: 48,
    totalBytes: 1099511627776,
    usedBytes: 429496729600,
    totalItems: 18432,
    totalImages: 15210,
    totalVideos: 3222,
    pendingJobs: 3,
  );

  static final List<AdminUser> _seedUsers = <AdminUser>[
    AdminUser(
      id: 'user-admin',
      email: 'admin@mynube.live',
      displayName: 'Admin Operator',
      role: UserRole.admin,
      storageUsed: 430 * 1024 * 1024 * 1024,
      quotaBytes: 1024 * 1024 * 1024 * 1024,
      active: true,
      createdAt: DateTime.utc(2024, 1, 1),
      lastLoginAt: DateTime.utc(2026, 3, 15, 8, 30),
    ),
    AdminUser(
      id: 'user-member',
      email: 'member@mynube.live',
      displayName: 'Family Member',
      role: UserRole.member,
      storageUsed: 12 * 1024 * 1024 * 1024,
      quotaBytes: 20 * 1024 * 1024 * 1024,
      active: true,
      createdAt: DateTime.utc(2024, 5, 10),
      lastLoginAt: DateTime.utc(2026, 3, 14, 19, 15),
    ),
    AdminUser(
      id: 'user-pending',
      email: 'pending@mynube.live',
      displayName: 'Pending Invite',
      role: UserRole.member,
      storageUsed: 0,
      quotaBytes: 10 * 1024 * 1024 * 1024,
      active: false,
      createdAt: DateTime.utc(2026, 3, 12),
    ),
  ];

  AdminStats _stats = _seedStats;
  final List<AdminUser> _users;
  AdminInviteResult? _latestInvite;
  bool _isLoading = false;
  bool _hasLoaded = false;
  bool _isLoadingUsers = false;
  bool _hasLoadedUsers = false;
  bool _isInviting = false;
  String? _errorMessage;
  String? _actionMessage;
  bool _actionMessageIsError = false;
  final Set<String> _savingUserIds = <String>{};
  final Set<String> _deactivatingUserIds = <String>{};

  AdminStats get stats => _stats;

  List<AdminUser> get users => List<AdminUser>.unmodifiable(_users);

  AdminInviteResult? get latestInvite => _latestInvite;

  bool get isLoading => _isLoading;

  bool get hasLoaded => _hasLoaded;

  bool get isLoadingUsers => _isLoadingUsers;

  bool get hasLoadedUsers => _hasLoadedUsers;

  bool get isInviting => _isInviting;

  bool get canManageUsers => _authProvider.canAccessAdmin;

  String? get errorMessage => _errorMessage;

  String? get actionMessage => _actionMessage;

  bool get actionMessageIsError => _actionMessageIsError;

  bool isSavingUser(String userId) => _savingUserIds.contains(userId);

  bool isDeactivatingUser(String userId) =>
      _deactivatingUserIds.contains(userId);

  bool isCurrentUser(String userId) => _authProvider.currentUser?.id == userId;

  final List<DeliveryLogEntry> recentBackendLogs = const <DeliveryLogEntry>[
    DeliveryLogEntry(
      dateLabel: 'Mar 14, 2026',
      title: 'MinIO public/internal endpoint split',
      description:
          'Presigned URLs now target minio.mynube.live while API and worker traffic stays on the Docker network.',
    ),
    DeliveryLogEntry(
      dateLabel: 'Mar 14, 2026',
      title: 'Media processing and SMTP invites finished',
      description:
          'The worker now promotes uploads, extracts metadata, generates thumbnails, schedules cleanup, and sends real invite emails.',
    ),
    DeliveryLogEntry(
      dateLabel: 'Mar 14, 2026',
      title: 'Profile writes and WebSocket progress',
      description:
          'PATCH /users/me, PUT /users/me/avatar, rate limiting, security headers, and /ws/progress are all live.',
    ),
    DeliveryLogEntry(
      dateLabel: 'Mar 15, 2026',
      title: 'Flutter multipart uploads and worker progress landed',
      description:
          'The client now uploads through the real multipart API, watches /ws/progress, and reconciles pending uploads back into the live media library.',
    ),
    DeliveryLogEntry(
      dateLabel: 'Mar 15, 2026',
      title: 'Flutter profile, album, and admin writes expanded',
      description:
          'The client now updates avatars, manages album shares and membership, persists native auth tokens, and exposes admin user-management flows.',
    ),
  ];

  final List<FlutterContinuation> nextFlutterContinuations =
      const <FlutterContinuation>[
    FlutterContinuation(
      title: 'Run live device coverage',
      description:
          'Native Android/iOS media picking is now wired, so the next highest-value step is running the new live upload/reconnect coverage with real backend credentials.',
      isHighestPriority: true,
    ),
    FlutterContinuation(
      title: 'Deepen automated coverage around live flows',
      description:
          'The next confidence win is widening the same device-level pattern to more directory-backed share dialogs, avatar refreshes, admin edits, and reconnect-sensitive flows.',
      isHighestPriority: false,
    ),
    FlutterContinuation(
      title: 'Tighten offline and cache behavior',
      description:
          'Signed URL caching now exists for avatars and thumbnails, and the next polish pass is carrying the same connectivity-aware UX into any remaining admin-only surfaces.',
      isHighestPriority: false,
    ),
  ];

  Future<void> load() async {
    if (_config.useDemoData) {
      _stats = _seedStats;
      _users
        ..clear()
        ..addAll(_seedUsers);
      _hasLoaded = true;
      _hasLoadedUsers = true;
      notifyListeners();
      return;
    }

    _isLoading = true;
    _isLoadingUsers = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final statsResponse = await _authProvider.withAuthorization(
        (headers) =>
            _transport.get(_apiClient.adminStatsUri(), headers: headers),
      );
      _stats = AdminStats.fromJson(statsResponse.asMap());
      _hasLoaded = true;

      await _loadUsersInternal();
    } on ApiException catch (error) {
      _errorMessage = error.message;
    } catch (_) {
      _errorMessage = 'Unable to load admin data right now.';
    } finally {
      _isLoading = false;
      _isLoadingUsers = false;
      notifyListeners();
    }
  }

  Future<void> loadUsers() async {
    if (_config.useDemoData) {
      _users
        ..clear()
        ..addAll(_seedUsers);
      _hasLoadedUsers = true;
      notifyListeners();
      return;
    }

    _isLoadingUsers = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _loadUsersInternal();
    } on ApiException catch (error) {
      _errorMessage = error.message;
    } catch (_) {
      _errorMessage = 'Unable to load the admin user list right now.';
    } finally {
      _isLoadingUsers = false;
      notifyListeners();
    }
  }

  Future<bool> inviteUser({
    required String email,
    required UserRole role,
    required int quotaGb,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    if (normalizedEmail.isEmpty) {
      _setActionMessage('Email is required.', isError: true);
      notifyListeners();
      return false;
    }
    if (quotaGb <= 0) {
      _setActionMessage('Quota must be greater than 0 GB.', isError: true);
      notifyListeners();
      return false;
    }

    _isInviting = true;
    _setActionMessage(null);
    notifyListeners();

    try {
      if (_config.useDemoData) {
        final invitedUser = AdminUser(
          id: 'user-${DateTime.now().microsecondsSinceEpoch}',
          email: normalizedEmail,
          displayName: normalizedEmail.split('@').first,
          role: role,
          storageUsed: 0,
          quotaBytes: quotaGb * 1024 * 1024 * 1024,
          active: false,
          createdAt: DateTime.now().toUtc(),
        );
        _users.insert(0, invitedUser);
        _latestInvite = AdminInviteResult(
          userId: invitedUser.id,
          inviteUrl: 'https://mynube.live/accept?token=demo-${invitedUser.id}',
          expiresAt: DateTime.now().toUtc().add(const Duration(hours: 72)),
        );
      } else {
        final response = await _authProvider.withAuthorization(
          (headers) => _transport.postJson(
            _apiClient.adminInviteUri(),
            headers: headers,
            body: <String, Object>{
              'email': normalizedEmail,
              'role': role.label,
              'quota_gb': quotaGb,
            },
          ),
        );
        _latestInvite = AdminInviteResult.fromJson(response.asMap());
        await _loadUsersInternal();
      }

      _setActionMessage('Invite created successfully.');
      notifyListeners();
      return true;
    } on ApiException catch (error) {
      _setActionMessage(error.message, isError: true);
      notifyListeners();
      return false;
    } catch (_) {
      _setActionMessage('Unable to create the invite right now.',
          isError: true);
      notifyListeners();
      return false;
    } finally {
      _isInviting = false;
      notifyListeners();
    }
  }

  Future<bool> updateUser({
    required String userId,
    UserRole? role,
    int? quotaBytes,
    bool? active,
  }) async {
    final payload = <String, Object>{};
    if (role != null) {
      payload['role'] = role.label;
    }
    if (quotaBytes != null) {
      payload['quota_bytes'] = quotaBytes;
    }
    if (active != null) {
      payload['active'] = active;
    }
    if (payload.isEmpty) {
      _setActionMessage('No account changes to save.');
      notifyListeners();
      return true;
    }

    _savingUserIds.add(userId);
    _setActionMessage(null);
    notifyListeners();

    try {
      AdminUser updatedUser;
      if (_config.useDemoData) {
        final index = _users.indexWhere((user) => user.id == userId);
        if (index == -1) {
          return false;
        }
        updatedUser = _users[index].copyWith(
          role: role,
          quotaBytes: quotaBytes,
          active: active,
        );
      } else {
        final response = await _authProvider.withAuthorization(
          (headers) => _transport.patchJson(
            _apiClient.adminUserUri(userId),
            headers: headers,
            body: payload,
          ),
        );
        updatedUser = AdminUser.fromJson(response.asMap());
      }

      _replaceUser(updatedUser);
      _setActionMessage('Account updated.');
      notifyListeners();
      return true;
    } on ApiException catch (error) {
      _setActionMessage(error.message, isError: true);
      notifyListeners();
      return false;
    } catch (_) {
      _setActionMessage('Unable to update the account right now.',
          isError: true);
      notifyListeners();
      return false;
    } finally {
      _savingUserIds.remove(userId);
      notifyListeners();
    }
  }

  Future<bool> deactivateUser(String userId) async {
    _deactivatingUserIds.add(userId);
    _setActionMessage(null);
    notifyListeners();

    try {
      if (!_config.useDemoData) {
        await _authProvider.withAuthorization(
          (headers) => _transport.delete(
            _apiClient.adminUserUri(userId),
            headers: headers,
          ),
        );
      }

      final index = _users.indexWhere((user) => user.id == userId);
      if (index != -1) {
        _users[index] = _users[index].copyWith(active: false);
      }
      _setActionMessage('Account deactivated.');
      notifyListeners();
      return true;
    } on ApiException catch (error) {
      _setActionMessage(error.message, isError: true);
      notifyListeners();
      return false;
    } catch (_) {
      _setActionMessage('Unable to deactivate the account right now.',
          isError: true);
      notifyListeners();
      return false;
    } finally {
      _deactivatingUserIds.remove(userId);
      notifyListeners();
    }
  }

  void reconcileCurrentUser(User user) {
    final index = _users.indexWhere((item) => item.id == user.id);
    if (index == -1) {
      return;
    }

    _users[index] = _users[index].copyWith(
      displayName: user.displayName,
      role: user.role,
      storageUsed: user.storageUsed,
      quotaBytes: user.quotaBytes,
      lastLoginAt: user.lastLoginAt,
    );
    notifyListeners();
  }

  void reset() {
    _stats = _seedStats;
    _users
      ..clear()
      ..addAll(_config.useDemoData ? _seedUsers : const <AdminUser>[]);
    _latestInvite = null;
    _isLoading = false;
    _hasLoaded = _config.useDemoData;
    _isLoadingUsers = false;
    _hasLoadedUsers = _config.useDemoData;
    _isInviting = false;
    _errorMessage = null;
    _actionMessage = null;
    _actionMessageIsError = false;
    _savingUserIds.clear();
    _deactivatingUserIds.clear();
    notifyListeners();
  }

  Future<void> _loadUsersInternal() async {
    final response = await _authProvider.withAuthorization(
      (headers) => _transport.get(_apiClient.adminUsersUri(), headers: headers),
    );
    final payload = response.asMap();
    final users = (payload['users'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map(AdminUser.fromJson)
        .toList(growable: false)
      ..sort((left, right) => left.email.compareTo(right.email));

    _users
      ..clear()
      ..addAll(users);
    _hasLoadedUsers = true;
  }

  void _replaceUser(AdminUser user) {
    final index = _users.indexWhere((item) => item.id == user.id);
    if (index == -1) {
      _users.add(user);
      _users.sort((left, right) => left.email.compareTo(right.email));
      return;
    }

    _users[index] = user;
    _users.sort((left, right) => left.email.compareTo(right.email));
  }

  void _setActionMessage(String? message, {bool isError = false}) {
    _actionMessage = message;
    _actionMessageIsError = isError;
  }
}

class DeliveryLogEntry {
  const DeliveryLogEntry({
    required this.dateLabel,
    required this.title,
    required this.description,
  });

  final String dateLabel;
  final String title;
  final String description;
}

class FlutterContinuation {
  const FlutterContinuation({
    required this.title,
    required this.description,
    required this.isHighestPriority,
  });

  final String title;
  final String description;
  final bool isHighestPriority;
}
