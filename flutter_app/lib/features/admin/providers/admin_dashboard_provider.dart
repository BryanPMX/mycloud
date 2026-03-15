import 'package:flutter/foundation.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/api_transport.dart';
import '../../auth/providers/auth_provider.dart';
import '../domain/admin_stats.dart';

class AdminDashboardProvider extends ChangeNotifier {
  AdminDashboardProvider({
    required AppConfig config,
    required ApiClient apiClient,
    required ApiTransport transport,
    required AuthProvider authProvider,
  })  : _config = config,
        _apiClient = apiClient,
        _transport = transport,
        _authProvider = authProvider;

  final AppConfig _config;
  final ApiClient _apiClient;
  final ApiTransport _transport;
  final AuthProvider _authProvider;

  static const AdminStats _seedStats = AdminStats(
    totalUsers: 52,
    activeUsers: 48,
    totalBytes: 1099511627776,
    usedBytes: 429496729600,
    totalItems: 18432,
    totalImages: 15210,
    totalVideos: 3222,
    pendingJobs: 3,
  );

  AdminStats _stats = _seedStats;
  bool _isLoading = false;
  bool _hasLoaded = false;
  String? _errorMessage;

  AdminStats get stats => _stats;

  bool get isLoading => _isLoading;

  bool get hasLoaded => _hasLoaded;

  String? get errorMessage => _errorMessage;

  final List<DeliveryLogEntry> recentBackendLogs = const <DeliveryLogEntry>[
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
      dateLabel: 'Mar 15, 2026',
      title: 'Flutter multipart uploads and worker progress landed',
      description:
          'The client now uploads through the real multipart API, watches /ws/progress, and reconciles pending uploads back into the live media library.',
    ),
  ];

  final List<FlutterContinuation> nextFlutterContinuations =
      const <FlutterContinuation>[
    FlutterContinuation(
      title: 'Land write flows for profile, comments, and album management',
      description:
          'The upload path is live now, so the next highest-value work is mutation UX, validation, and optimistic updates for the remaining user-facing writes.',
      isHighestPriority: true,
    ),
    FlutterContinuation(
      title: 'Add native token persistence',
      description:
          'Web can restore sessions with cookies, but mobile still needs secure storage for refresh-token persistence across app restarts.',
      isHighestPriority: false,
    ),
    FlutterContinuation(
      title: 'Expand admin beyond stats',
      description:
          'GET /admin/users, invite delivery, and account updates are ready to be surfaced in operator screens next.',
      isHighestPriority: false,
    ),
    FlutterContinuation(
      title: 'Deepen automated coverage around live flows',
      description:
          'The next confidence win is widget and integration coverage for upload happy paths, reconnect handling, and the remaining live mutations.',
      isHighestPriority: false,
    ),
  ];

  Future<void> load() async {
    if (_config.useDemoData) {
      _stats = _seedStats;
      _hasLoaded = true;
      notifyListeners();
      return;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final response = await _authProvider.withAuthorization(
        (headers) =>
            _transport.get(_apiClient.adminStatsUri(), headers: headers),
      );
      _stats = AdminStats.fromJson(response.asMap());
      _hasLoaded = true;
    } on ApiException catch (error) {
      _errorMessage = error.message;
    } catch (_) {
      _errorMessage = 'Unable to load admin stats right now.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void reset() {
    _stats = _seedStats;
    _isLoading = false;
    _hasLoaded = _config.useDemoData;
    _errorMessage = null;
    notifyListeners();
  }
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
