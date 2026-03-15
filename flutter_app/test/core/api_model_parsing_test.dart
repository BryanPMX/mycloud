import 'package:familycloud/features/admin/domain/admin_invite_result.dart';
import 'package:familycloud/features/admin/domain/admin_stats.dart';
import 'package:familycloud/features/admin/domain/admin_user.dart';
import 'package:familycloud/features/albums/domain/album_share.dart';
import 'package:familycloud/features/auth/domain/user.dart';
import 'package:familycloud/features/comments/domain/comment.dart';
import 'package:familycloud/features/media/domain/media.dart';
import 'package:familycloud/core/websocket/upload_progress_event.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('User.fromJson maps the live DTO shape', () {
    final user = User.fromJson(<String, dynamic>{
      'id': 'user-1',
      'email': 'member@mynube.live',
      'display_name': 'Family Member',
      'avatar_url': 'users/user-1/avatar.png',
      'role': 'member',
      'storage_used': 1024,
      'quota_bytes': 2048,
      'created_at': '2026-03-14T16:00:00Z',
      'last_login_at': '2026-03-15T08:30:00Z',
    });

    expect(user.id, 'user-1');
    expect(user.role, UserRole.member);
    expect(user.storagePct, 0.5);
    expect(user.lastLoginAt, DateTime.parse('2026-03-15T08:30:00Z'));
  });

  test('Media.fromJson keeps duration precision and thumb keys', () {
    final media = Media.fromJson(<String, dynamic>{
      'id': 'media-1',
      'owner_id': 'user-1',
      'filename': 'lake-walk.mov',
      'mime_type': 'video/quicktime',
      'size_bytes': 248034123,
      'width': 1920,
      'height': 1080,
      'duration_secs': 48.4,
      'status': 'pending',
      'is_favorite': false,
      'taken_at': '2026-03-14T16:00:00Z',
      'uploaded_at': '2026-03-14T16:05:00Z',
      'thumb_urls': <String, dynamic>{'poster': 'media-1/poster.webp'},
    });

    expect(media.durationSecs, 48.4);
    expect(media.status, MediaStatus.pending);
    expect(media.thumbUrls.poster, 'media-1/poster.webp');
  });

  test('Comment.fromJson uses the dedicated author shape', () {
    final comment = Comment.fromJson(<String, dynamic>{
      'id': 'comment-1',
      'author': <String, dynamic>{
        'id': 'user-1',
        'display_name': 'Family Member',
        'avatar_url': null,
      },
      'body': 'Great shot!',
      'created_at': '2026-03-15T09:00:00Z',
    });

    expect(comment.author.id, 'user-1');
    expect(comment.author.displayName, 'Family Member');
    expect(comment.body, 'Great shot!');
  });

  test('AdminStats.fromJson maps nested DTO sections', () {
    final stats = AdminStats.fromJson(<String, dynamic>{
      'users': <String, dynamic>{'total': 52, 'active': 48},
      'storage': <String, dynamic>{
        'total_bytes': 1000,
        'used_bytes': 250,
        'free_bytes': 750,
        'pct_used': 25.0,
      },
      'media': <String, dynamic>{
        'total_items': 32,
        'total_images': 20,
        'total_videos': 12,
        'pending_jobs': 3,
      },
    });

    expect(stats.totalUsers, 52);
    expect(stats.pendingJobs, 3);
    expect(stats.pctUsed, 0.25);
  });

  test('AdminUser.fromJson maps admin account DTOs', () {
    final user = AdminUser.fromJson(<String, dynamic>{
      'id': 'user-2',
      'email': 'admin@mynube.live',
      'display_name': 'Admin Operator',
      'role': 'admin',
      'storage_used': 2048,
      'quota_bytes': 4096,
      'active': true,
      'created_at': '2026-03-14T16:00:00Z',
      'last_login_at': '2026-03-15T08:30:00Z',
    });

    expect(user.isAdmin, isTrue);
    expect(user.quotaBytes, 4096);
    expect(user.lastLoginAt, DateTime.parse('2026-03-15T08:30:00Z'));
  });

  test('AdminInviteResult.fromJson keeps invite fallback fields', () {
    final invite = AdminInviteResult.fromJson(<String, dynamic>{
      'user_id': 'user-3',
      'invite_url': 'https://mynube.live/accept?token=abc123',
      'expires_at': '2026-03-18T18:00:00Z',
    });

    expect(invite.userId, 'user-3');
    expect(invite.inviteUrl, contains('token=abc123'));
  });

  test('AlbumShare.fromJson maps family share responses', () {
    final share = AlbumShare.fromJson(<String, dynamic>{
      'id': 'share-1',
      'album_id': 'album-1',
      'shared_by': 'user-admin',
      'shared_with': '00000000-0000-0000-0000-000000000000',
      'recipient': <String, dynamic>{
        'id': '00000000-0000-0000-0000-000000000000',
        'display_name': 'Entire family',
        'avatar_url': null,
      },
      'permission': 'contribute',
      'expires_at': null,
      'created_at': '2026-03-15T10:00:00Z',
    });

    expect(share.isFamilyShare, isTrue);
    expect(share.permission, AlbumPermission.contribute);
    expect(share.recipient?.displayName, 'Entire family');
  });

  test('UploadProgressEvent.fromJson maps worker websocket payloads', () {
    final event = UploadProgressEvent.fromJson(<String, dynamic>{
      'type': 'processing_complete',
      'media_id': 'media-1',
      'status': 'ready',
      'thumb_urls': <String, dynamic>{
        'small': 'media-1/small.webp',
        'medium': 'media-1/medium.webp',
        'poster': 'media-1/poster.webp',
      },
    });

    expect(event.type, UploadProgressEventType.processingComplete);
    expect(event.mediaId, 'media-1');
    expect(event.status, 'ready');
    expect(event.thumbKeys?.medium, 'media-1/medium.webp');
    expect(event.thumbKeys?.poster, 'media-1/poster.webp');
  });
}
