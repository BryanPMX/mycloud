import 'package:flutter/foundation.dart';

import '../../../core/config/app_config.dart';
import '../domain/user.dart';

enum AuthStatus { restoring, signedOut, signingIn, signedIn }

class AuthProvider extends ChangeNotifier {
  AuthProvider({required AppConfig config}) : _config = config;

  final AppConfig _config;

  AuthStatus _status = AuthStatus.restoring;
  User? _currentUser;
  String? _errorMessage;

  AuthStatus get status => _status;

  User? get currentUser => _currentUser;

  String? get errorMessage => _errorMessage;

  bool get isBusy =>
      _status == AuthStatus.restoring || _status == AuthStatus.signingIn;

  bool get isAuthenticated => _currentUser != null;

  bool get canAccessAdmin => _currentUser?.isAdmin ?? false;

  Future<void> restore() async {
    _status = AuthStatus.restoring;
    _errorMessage = null;
    notifyListeners();
    await Future<void>.delayed(const Duration(milliseconds: 120));
    _status = AuthStatus.signedOut;
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

  Future<void> signInAsDemoMember() {
    return signIn(
      email: 'member@mynube.live',
      password: _config.useDemoData ? 'demo-password' : 'password',
    );
  }

  Future<void> signInAsDemoAdmin() {
    return signIn(
      email: 'admin@mynube.live',
      password: _config.useDemoData ? 'demo-password' : 'password',
    );
  }

  void signOut() {
    _currentUser = null;
    _errorMessage = null;
    _status = AuthStatus.signedOut;
    notifyListeners();
  }
}
