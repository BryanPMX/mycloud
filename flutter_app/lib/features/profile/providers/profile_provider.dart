import 'package:flutter/foundation.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_client.dart';
import '../../admin/providers/admin_dashboard_provider.dart';
import '../../auth/domain/user.dart';
import '../../auth/providers/auth_provider.dart';

class ProfileProvider extends ChangeNotifier {
  ProfileProvider({
    required this.config,
    required this.apiClient,
    required this.authProvider,
    required this.adminProvider,
  }) {
    authProvider.addListener(_handleAuthChanged);
  }

  final AppConfig config;
  final ApiClient apiClient;
  final AuthProvider authProvider;
  final AdminDashboardProvider adminProvider;

  User? get currentUser => authProvider.currentUser;

  List<ProfileEndpoint> get endpoints => [
        ProfileEndpoint(label: 'App', uri: config.appBaseUri),
        ProfileEndpoint(label: 'Login', uri: apiClient.loginUri()),
        ProfileEndpoint(label: 'Current user', uri: apiClient.currentUserUri()),
        ProfileEndpoint(label: 'Media list', uri: apiClient.mediaListUri()),
        ProfileEndpoint(label: 'Albums', uri: apiClient.albumsUri()),
        ProfileEndpoint(label: 'Admin stats', uri: apiClient.adminStatsUri()),
      ];

  List<RolloutStep> get rolloutSteps => const [
        RolloutStep(
          title: 'Foundation shell and Router',
          description:
              'Completed in this slice so the web app has route-aware bootstrapping and adaptive navigation.',
          done: true,
        ),
        RolloutStep(
          title: 'Auth API wiring',
          description:
              'Connect the login form and session restore flow to /auth/login, /auth/refresh, and /users/me.',
          done: false,
        ),
        RolloutStep(
          title: 'Media reads and presigned thumbnails',
          description:
              'Swap seeded cards for GET /media and GET /media/:id/thumb so the library reflects real storage state.',
          done: false,
        ),
        RolloutStep(
          title: 'Multipart upload and processing events',
          description:
              'Implement the /media/upload lifecycle and consume /ws/progress for worker-side processing status.',
          done: false,
        ),
      ];

  void _handleAuthChanged() {
    notifyListeners();
  }

  @override
  void dispose() {
    authProvider.removeListener(_handleAuthChanged);
    super.dispose();
  }
}

class ProfileEndpoint {
  const ProfileEndpoint({required this.label, required this.uri});

  final String label;
  final Uri uri;
}

class RolloutStep {
  const RolloutStep({
    required this.title,
    required this.description,
    required this.done,
  });

  final String title;
  final String description;
  final bool done;
}
