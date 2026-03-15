class AdminInviteResult {
  const AdminInviteResult({
    required this.userId,
    required this.inviteUrl,
    required this.expiresAt,
  });

  final String userId;
  final String inviteUrl;
  final DateTime expiresAt;

  factory AdminInviteResult.fromJson(Map<String, dynamic> json) {
    return AdminInviteResult(
      userId: json['user_id'] as String? ?? '',
      inviteUrl: json['invite_url'] as String? ?? '',
      expiresAt: DateTime.tryParse(json['expires_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }
}
