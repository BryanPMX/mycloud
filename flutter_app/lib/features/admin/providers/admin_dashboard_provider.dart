import 'package:flutter/foundation.dart';

import '../domain/admin_stats.dart';

class AdminDashboardProvider extends ChangeNotifier {
  final AdminStats stats = const AdminStats(
    totalUsers: 52,
    activeUsers: 48,
    totalBytes: 1099511627776,
    usedBytes: 429496729600,
    totalItems: 18432,
    totalImages: 15210,
    totalVideos: 3222,
    pendingJobs: 3,
  );

  final List<DeliveryLogEntry> recentBackendLogs = const [
    DeliveryLogEntry(
      dateLabel: 'Mar 14, 2026',
      title: 'MinIO public/internal endpoint split',
      description:
          'Presigned URLs now target minio.mynube.live while API and worker traffic stays on the Docker network.',
    ),
    DeliveryLogEntry(
      dateLabel: 'Mar 14, 2026',
      title: 'Media processing and SMTP invites finished',
      description:
          'The worker now promotes uploads, extracts metadata, generates thumbnails, schedules cleanup, and sends real invite emails.',
    ),
    DeliveryLogEntry(
      dateLabel: 'Mar 14, 2026',
      title: 'Profile writes and WebSocket progress',
      description:
          'PATCH /users/me, PUT /users/me/avatar, rate limiting, security headers, and /ws/progress are all live.',
    ),
    DeliveryLogEntry(
      dateLabel: 'Mar 14, 2026',
      title: 'Admin invite onboarding and audit logs',
      description:
          'Invite acceptance, admin user management, and audit persistence are now in place.',
    ),
  ];

  final List<FlutterContinuation> nextFlutterContinuations = const [
    FlutterContinuation(
      title: 'Wire auth + session restore first',
      description:
          'POST /auth/login, POST /auth/refresh, and GET /users/me unlock every protected client route.',
      isHighestPriority: true,
    ),
    FlutterContinuation(
      title: 'Replace seeded media cards with live media reads',
      description:
          'GET /media, GET /media/search, and GET /media/:id/thumb should back the library immediately after auth.',
      isHighestPriority: true,
    ),
    FlutterContinuation(
      title: 'Land direct upload and processing status',
      description:
          'The multipart upload endpoints and /ws/progress are ready for a client-side upload manager.',
      isHighestPriority: false,
    ),
    FlutterContinuation(
      title: 'Finish profile, albums, comments, and admin CRUD',
      description:
          'Those APIs already exist, so the rest of the work is mostly integration, optimistic UX, and validation.',
      isHighestPriority: false,
    ),
  ];
}

class DeliveryLogEntry {
  const DeliveryLogEntry({
    required this.dateLabel,
    required this.title,
    required this.description,
  });

  final String dateLabel;
  final String title;
  final String description;
}

class FlutterContinuation {
  const FlutterContinuation({
    required this.title,
    required this.description,
    required this.isHighestPriority,
  });

  final String title;
  final String description;
  final bool isHighestPriority;
}
