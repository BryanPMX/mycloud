class DirectoryUser {
  const DirectoryUser({
    required this.id,
    required this.displayName,
    this.avatarUrl,
  });

  final String id;
  final String displayName;
  final String? avatarUrl;

  DirectoryUser copyWith({
    String? displayName,
    String? avatarUrl,
    bool replaceAvatarUrl = false,
  }) {
    return DirectoryUser(
      id: id,
      displayName: displayName ?? this.displayName,
      avatarUrl: replaceAvatarUrl ? avatarUrl : avatarUrl ?? this.avatarUrl,
    );
  }

  factory DirectoryUser.fromJson(Map<String, dynamic> json) {
    return DirectoryUser(
      id: json['id'] as String? ?? '',
      displayName: json['display_name'] as String? ?? '',
      avatarUrl: json['avatar_url'] as String?,
    );
  }
}
