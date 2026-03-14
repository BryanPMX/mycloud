import '../../auth/domain/user.dart';

class Comment {
  const Comment({
    required this.id,
    required this.author,
    required this.body,
    required this.createdAt,
  });

  final String id;
  final User author;
  final String body;
  final DateTime createdAt;
}
