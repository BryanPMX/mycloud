enum UserRole {
  admin('admin'),
  member('member');

  const UserRole(this.label);

  final String label;

  static UserRole fromApi(Object? value) {
    return value == 'admin' ? UserRole.admin : UserRole.member;
  }
}

class User {
  const User({
    required this.id,
    required this.email,
    required this.displayName,
    required this.role,
    required this.storageUsed,
    required this.quotaBytes,
    required this.createdAt,
    this.avatarUrl,
    this.lastLoginAt,
  });

  final String id;
  final String email;
  final String displayName;
  final String? avatarUrl;
  final UserRole role;
  final int storageUsed;
  final int quotaBytes;
  final DateTime createdAt;
  final DateTime? lastLoginAt;

  bool get isAdmin => role == UserRole.admin;

  double get storagePct => quotaBytes == 0 ? 0 : storageUsed / quotaBytes;

  User copyWith({
    String? displayName,
    String? avatarUrl,
    int? storageUsed,
    int? quotaBytes,
    DateTime? lastLoginAt,
  }) {
    return User(
      id: id,
      email: email,
      displayName: displayName ?? this.displayName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      role: role,
      storageUsed: storageUsed ?? this.storageUsed,
      quotaBytes: quotaBytes ?? this.quotaBytes,
      createdAt: createdAt,
      lastLoginAt: lastLoginAt ?? this.lastLoginAt,
    );
  }

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String? ?? '',
      email: json['email'] as String? ?? '',
      displayName: json['display_name'] as String? ?? '',
      avatarUrl: json['avatar_url'] as String?,
      role: UserRole.fromApi(json['role']),
      storageUsed: _asInt(json['storage_used']),
      quotaBytes: _asInt(json['quota_bytes']),
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
