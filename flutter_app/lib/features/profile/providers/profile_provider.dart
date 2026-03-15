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
          title: 'Auth API wiring and session restore',
          description:
              'The app now signs in against /auth/login and restores browser sessions through /auth/refresh plus /users/me.',
          done: true,
        ),
        RolloutStep(
          title: 'Media, albums, comments, and admin stats reads',
          description:
              'Read surfaces now come from the live backend, including /media, /media/search, /media/:id/thumb, /albums, /media/:id/comments, and /admin/stats.',
          done: true,
        ),
        RolloutStep(
          title: 'Multipart upload and processing events',
          description:
              'Implement the /media/upload lifecycle and consume /ws/progress for worker-side processing status.',
          done: false,
        ),
        RolloutStep(
          title: 'Write flows and native session persistence',
          description:
              'Profile edits, album management, comment creation, and secure mobile token storage are the next production-grade client gaps.',
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
