import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorage {
  SecureStorage({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(),
            );

  static const String _accessTokenKey = 'auth.access_token';
  static const String _refreshTokenKey = 'auth.refresh_token';

  final FlutterSecureStorage _storage;

  bool get supportsSecurePersistence => !kIsWeb;

  Future<String?> readAccessToken() async {
    if (!supportsSecurePersistence) {
      return null;
    }
    return _storage.read(key: _accessTokenKey);
  }

  Future<String?> readRefreshToken() async {
    if (!supportsSecurePersistence) {
      return null;
    }
    return _storage.read(key: _refreshTokenKey);
  }

  Future<void> saveTokens({
    String? accessToken,
    String? refreshToken,
  }) async {
    if (!supportsSecurePersistence) {
      return;
    }

    if (accessToken == null || accessToken.trim().isEmpty) {
      await _storage.delete(key: _accessTokenKey);
    } else {
      await _storage.write(key: _accessTokenKey, value: accessToken);
    }

    if (refreshToken == null || refreshToken.trim().isEmpty) {
      await _storage.delete(key: _refreshTokenKey);
    } else {
      await _storage.write(key: _refreshTokenKey, value: refreshToken);
    }
  }

  Future<void> clearTokens() async {
    if (!supportsSecurePersistence) {
      return;
    }

    await Future.wait<void>(<Future<void>>[
      _storage.delete(key: _accessTokenKey),
      _storage.delete(key: _refreshTokenKey),
    ]);
  }
}
