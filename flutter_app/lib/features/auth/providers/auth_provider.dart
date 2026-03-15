import 'package:flutter/foundation.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/api_transport.dart';
import '../domain/user.dart';

enum AuthStatus { restoring, signedOut, signingIn, signedIn }

class AuthProvider extends ChangeNotifier {
  AuthProvider({
    required AppConfig config,
    required ApiClient apiClient,
    required ApiTransport transport,
  })  : _config = config,
        _apiClient = apiClient,
        _transport = transport;

  final AppConfig _config;
  final ApiClient _apiClient;
  final ApiTransport _transport;

  AuthStatus _status = AuthStatus.restoring;
  User? _currentUser;
  String? _accessToken;
  String? _refreshToken;
  String? _errorMessage;

  AuthStatus get status => _status;

  User? get currentUser => _currentUser;

  String? get errorMessage => _errorMessage;

  bool get isBusy =>
      _status == AuthStatus.restoring || _status == AuthStatus.signingIn;

  bool get isAuthenticated => _currentUser != null;

  bool get canAccessAdmin => _currentUser?.isAdmin ?? false;

  bool get usesDemoData => _config.useDemoData;

  void updateCurrentUser(User user) {
    _currentUser = user;
    _status = AuthStatus.signedIn;
    _errorMessage = null;
    notifyListeners();
  }

  Future<void> restore() async {
    _status = AuthStatus.restoring;
    _errorMessage = null;
    notifyListeners();

    if (_config.useDemoData) {
      _status = AuthStatus.signedOut;
      notifyListeners();
      return;
    }

    try {
      _currentUser = await _restoreCurrentUser();
      _status = AuthStatus.signedIn;
    } on ApiException catch (error) {
      _clearSession();
      _status = AuthStatus.signedOut;
      if (!error.isUnauthorized) {
        _errorMessage = error.message;
      }
    } catch (_) {
      _clearSession();
      _status = AuthStatus.signedOut;
      _errorMessage = 'Unable to restore the current session.';
    }

    notifyListeners();
  }

  Future<void> signIn({required String email, required String password}) async {
    final normalizedEmail = email.trim().toLowerCase();
    if (normalizedEmail.isEmpty || password.isEmpty) {
      _errorMessage = 'Email and password are required.';
      _status = AuthStatus.signedOut;
      notifyListeners();
      return;
    }

    if (_config.useDemoData) {
      await _signInDemo(normalizedEmail);
      return;
    }

    _status = AuthStatus.signingIn;
    _errorMessage = null;
    notifyListeners();

    try {
      final response = await _transport.postJson(
        _apiClient.loginUri(),
        body: <String, String>{
          'email': normalizedEmail,
          'password': password,
        },
      );
      final payload = response.asMap();
      _accessToken = payload['access_token'] as String?;
      _refreshToken = payload['refresh_token'] as String?;
      _currentUser = User.fromJson(
        payload['user'] as Map<String, dynamic>? ?? const <String, dynamic>{},
      );
      _status = AuthStatus.signedIn;
    } on ApiException catch (error) {
      _clearSession();
      _status = AuthStatus.signedOut;
      _errorMessage = error.message;
    } catch (_) {
      _clearSession();
      _status = AuthStatus.signedOut;
      _errorMessage = 'Unable to sign in right now.';
    }

    notifyListeners();
  }

  Future<void> signInAsDemoMember() {
    return signIn(
      email: 'member@mynube.live',
      password: usesDemoData ? 'demo-password' : 'password',
    );
  }

  Future<void> signInAsDemoAdmin() {
    return signIn(
      email: 'admin@mynube.live',
      password: usesDemoData ? 'demo-password' : 'password',
    );
  }

  Future<void> signOut() async {
    if (_config.useDemoData) {
      _clearSession();
      _status = AuthStatus.signedOut;
      notifyListeners();
      return;
    }

    try {
      await _transport.postJson(
        _apiClient.logoutUri(),
        body: _refreshToken == null || kIsWeb
            ? const <String, Object?>{}
            : <String, String>{'refresh_token': _refreshToken!},
        headers: _authorizationHeaders(),
      );
    } catch (_) {
      // Clear the local session even if the remote revoke fails.
    }

    _clearSession();
    _status = AuthStatus.signedOut;
    notifyListeners();
  }

  Future<T> withAuthorization<T>(
    Future<T> Function(Map<String, String> headers) action,
  ) async {
    try {
      return await action(_authorizationHeaders());
    } on ApiException catch (error) {
      if (!error.isUnauthorized) {
        rethrow;
      }

      final refreshed = await _refreshSession();
      if (!refreshed) {
        _clearSession();
        _status = AuthStatus.signedOut;
        notifyListeners();
        rethrow;
      }

      return action(_authorizationHeaders());
    }
  }

  Future<Map<String, String>> websocketHeaders() async {
    if (_config.useDemoData || !_currentUserIsActive) {
      return const <String, String>{};
    }

    if (kIsWeb) {
      return const <String, String>{};
    }

    if (_accessToken == null || _accessToken!.trim().isEmpty) {
      final refreshed = await _refreshSession();
      if (!refreshed) {
        _clearSession();
        _status = AuthStatus.signedOut;
        notifyListeners();
        return const <String, String>{};
      }
    }

    return _authorizationHeaders();
  }

  Future<User> _restoreCurrentUser() async {
    try {
      return await _fetchCurrentUser();
    } on ApiException catch (error) {
      if (!error.isUnauthorized) {
        rethrow;
      }

      final refreshed = await _refreshSession();
      if (!refreshed) {
        rethrow;
      }

      return _fetchCurrentUser();
    }
  }

  Future<User> _fetchCurrentUser() async {
    final response = await _transport.get(
      _apiClient.currentUserUri(),
      headers: _authorizationHeaders(),
    );
    return User.fromJson(response.asMap());
  }

  Future<bool> _refreshSession() async {
    try {
      final response = await _transport.postJson(
        _apiClient.refreshUri(),
        body: kIsWeb || _refreshToken == null
            ? const <String, Object?>{}
            : <String, String>{'refresh_token': _refreshToken!},
        headers: _authorizationHeaders(),
      );
      final payload = response.asMap();
      _accessToken = payload['access_token'] as String?;
      _refreshToken = payload['refresh_token'] as String? ?? _refreshToken;
      return true;
    } on ApiException {
      return false;
    }
  }

  Future<void> _signInDemo(String normalizedEmail) async {
    _status = AuthStatus.signingIn;
    _errorMessage = null;
    notifyListeners();
    await Future<void>.delayed(const Duration(milliseconds: 260));

    final isAdmin = normalizedEmail.contains('admin');
    final quotaBytes =
        isAdmin ? 1024 * 1024 * 1024 * 1024 : 20 * 1024 * 1024 * 1024;
    final storageUsed =
        isAdmin ? 430 * 1024 * 1024 * 1024 : 12 * 1024 * 1024 * 1024;

    _currentUser = User(
      id: isAdmin ? 'user-admin' : 'user-member',
      email: normalizedEmail,
      displayName: isAdmin ? 'Admin Operator' : 'Family Member',
      avatarUrl: null,
      role: isAdmin ? UserRole.admin : UserRole.member,
      storageUsed: storageUsed,
      quotaBytes: quotaBytes,
      createdAt: DateTime.utc(2024, 1, 1),
      lastLoginAt: DateTime.utc(2026, 3, 14, 16, 30),
    );
    _status = AuthStatus.signedIn;
    notifyListeners();
  }

  Map<String, String> _authorizationHeaders() {
    if (_accessToken == null || _accessToken!.trim().isEmpty) {
      return const <String, String>{'Accept': 'application/json'};
    }

    return <String, String>{
      'Accept': 'application/json',
      'Authorization': 'Bearer $_accessToken',
    };
  }

  bool get _currentUserIsActive => _currentUser != null;

  void _clearSession() {
    _currentUser = null;
    _accessToken = null;
    _refreshToken = null;
    _errorMessage = null;
  }
}
