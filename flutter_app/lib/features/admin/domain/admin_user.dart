import '../../auth/domain/user.dart';

class AdminUser {
  const AdminUser({
    required this.id,
    required this.email,
    required this.displayName,
    required this.role,
    required this.storageUsed,
    required this.quotaBytes,
    required this.active,
    required this.createdAt,
    this.lastLoginAt,
  });

  final String id;
  final String email;
  final String displayName;
  final UserRole role;
  final int storageUsed;
  final int quotaBytes;
  final bool active;
  final DateTime createdAt;
  final DateTime? lastLoginAt;

  bool get isAdmin => role == UserRole.admin;

  AdminUser copyWith({
    String? displayName,
    UserRole? role,
    int? storageUsed,
    int? quotaBytes,
    bool? active,
    DateTime? lastLoginAt,
  }) {
    return AdminUser(
      id: id,
      email: email,
      displayName: displayName ?? this.displayName,
      role: role ?? this.role,
      storageUsed: storageUsed ?? this.storageUsed,
      quotaBytes: quotaBytes ?? this.quotaBytes,
      active: active ?? this.active,
      createdAt: createdAt,
      lastLoginAt: lastLoginAt ?? this.lastLoginAt,
    );
  }

  factory AdminUser.fromJson(Map<String, dynamic> json) {
    return AdminUser(
      id: json['id'] as String? ?? '',
      email: json['email'] as String? ?? '',
      displayName: json['display_name'] as String? ?? '',
      role: UserRole.fromApi(json['role']),
      storageUsed: _asInt(json['storage_used']),
      quotaBytes: _asInt(json['quota_bytes']),
      active: json['active'] as bool? ?? false,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      lastLoginAt: DateTime.tryParse(json['last_login_at'] as String? ?? ''),
    );
  }

  static int _asInt(Object? value) {
    if (value is num) {
      return value.toInt();
    }

    return 0;
  }
}
