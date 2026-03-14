enum UserRole {
  admin('admin'),
  member('member');

  const UserRole(this.label);

  final String label;
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
}
