import '../../media/domain/media.dart';

class Family {
  const Family({required this.id, required this.name, required this.role});
  final String id;
  final String name;
  final String role;
  bool get canInvite => role == 'owner' || role == 'admin';
  factory Family.fromJson(Map<String, dynamic> json) => Family(
      id: json['id'] as String,
      name: json['name'] as String,
      role: json['role'] as String);
}

class FamilyPost {
  const FamilyPost(
      {required this.id,
      required this.authorId,
      required this.authorName,
      required this.caption,
      required this.createdAt,
      required this.media});
  final String id;
  final String authorId;
  final String authorName;
  final String caption;
  final DateTime createdAt;
  final List<Media> media;
  factory FamilyPost.fromJson(Map<String, dynamic> json) => FamilyPost(
      id: json['id'] as String,
      authorId: json['author_id'] as String,
      authorName: json['author_name'] as String,
      caption: json['caption'] as String? ?? '',
      createdAt: DateTime.parse(json['created_at'] as String),
      media: (json['media'] as List<dynamic>)
          .map((item) => Media.fromJson(item as Map<String, dynamic>))
          .toList());
}
