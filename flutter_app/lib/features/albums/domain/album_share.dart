enum AlbumPermission {
  view('view'),
  contribute('contribute');

  const AlbumPermission(this.apiValue);

  final String apiValue;

  String get label => apiValue;

  static AlbumPermission fromApi(Object? value) {
    return value == 'contribute'
        ? AlbumPermission.contribute
        : AlbumPermission.view;
  }
}

class AlbumShareRecipient {
  const AlbumShareRecipient({
    required this.id,
    required this.displayName,
    this.avatarUrl,
  });

  final String id;
  final String displayName;
  final String? avatarUrl;

  bool get isEntireFamily => id == AlbumShare.familyRecipientId;

  factory AlbumShareRecipient.fromJson(Map<String, dynamic> json) {
    return AlbumShareRecipient(
      id: json['id'] as String? ?? '',
      displayName: json['display_name'] as String? ?? '',
      avatarUrl: json['avatar_url'] as String?,
    );
  }
}

class AlbumShare {
  const AlbumShare({
    required this.id,
    required this.albumId,
    required this.sharedBy,
    required this.sharedWith,
    required this.permission,
    required this.createdAt,
    this.recipient,
    this.expiresAt,
  });

  static const String familyRecipientId =
      '00000000-0000-0000-0000-000000000000';

  final String id;
  final String albumId;
  final String sharedBy;
  final String sharedWith;
  final AlbumPermission permission;
  final DateTime createdAt;
  final AlbumShareRecipient? recipient;
  final DateTime? expiresAt;

  bool get isFamilyShare =>
      sharedWith == familyRecipientId || recipient?.isEntireFamily == true;

  factory AlbumShare.fromJson(Map<String, dynamic> json) {
    final recipientJson = json['recipient'] as Map<String, dynamic>?;

    return AlbumShare(
      id: json['id'] as String? ?? '',
      albumId: json['album_id'] as String? ?? '',
      sharedBy: json['shared_by'] as String? ?? '',
      sharedWith: json['shared_with'] as String? ?? '',
      permission: AlbumPermission.fromApi(json['permission']),
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      recipient: recipientJson == null
          ? null
          : AlbumShareRecipient.fromJson(recipientJson),
      expiresAt: DateTime.tryParse(json['expires_at'] as String? ?? ''),
    );
  }
}
