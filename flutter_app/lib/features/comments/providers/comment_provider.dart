import 'package:flutter/foundation.dart';

import '../../auth/domain/user.dart';
import '../domain/comment.dart';

class CommentProvider extends ChangeNotifier {
  final Map<String, List<Comment>> _commentsByMediaId = {
    'media-1': [
      Comment(
        id: 'comment-1',
        author: User(
          id: 'user-admin',
          email: 'admin@mynube.live',
          displayName: 'Admin Operator',
          avatarUrl: null,
          role: UserRole.admin,
          storageUsed: 0,
          quotaBytes: 1,
          createdAt: DateTime.utc(2024, 1, 1),
        ),
        body:
            'This is a strong candidate for the library hero tile once live thumbs land.',
        createdAt: DateTime.utc(2026, 3, 14, 16, 12),
      ),
      Comment(
        id: 'comment-2',
        author: User(
          id: 'user-member',
          email: 'member@mynube.live',
          displayName: 'Family Member',
          avatarUrl: null,
          role: UserRole.member,
          storageUsed: 0,
          quotaBytes: 1,
          createdAt: DateTime.utc(2024, 1, 1),
        ),
        body:
            'Once /media/:id/url is wired, this detail panel can open originals directly.',
        createdAt: DateTime.utc(2026, 3, 14, 16, 18),
      ),
    ],
    'media-2': [
      Comment(
        id: 'comment-3',
        author: User(
          id: 'user-admin',
          email: 'admin@mynube.live',
          displayName: 'Admin Operator',
          avatarUrl: null,
          role: UserRole.admin,
          storageUsed: 0,
          quotaBytes: 1,
          createdAt: DateTime.utc(2024, 1, 1),
        ),
        body:
            'This item is intentionally pending so the upload-progress slice has something to mirror.',
        createdAt: DateTime.utc(2026, 3, 14, 16, 20),
      ),
    ],
  };

  List<Comment> commentsFor(String mediaId) {
    return _commentsByMediaId[mediaId] ?? const [];
  }
}
