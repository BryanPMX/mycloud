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
}
