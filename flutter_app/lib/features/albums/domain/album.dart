class Album {
  const Album({
    required this.id,
    required this.ownerId,
    required this.name,
    required this.description,
    required this.mediaCount,
    required this.createdAt,
    required this.updatedAt,
    required this.isOwnedByCurrentUser,
    this.coverMediaId,
  });

  final String id;
  final String ownerId;
  final String name;
  final String description;
  final String? coverMediaId;
  final int mediaCount;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isOwnedByCurrentUser;

  factory Album.fromJson(
    Map<String, dynamic> json, {
    required bool isOwnedByCurrentUser,
  }) {
    return Album(
      id: json['id'] as String? ?? '',
      ownerId: json['owner_id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      coverMediaId: json['cover_media_id'] as String?,
      mediaCount: _asInt(json['media_count']),
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      isOwnedByCurrentUser: isOwnedByCurrentUser,
    );
  }

  static int _asInt(Object? value) {
    if (value is num) {
      return value.toInt();
    }

    return 0;
  }
}
