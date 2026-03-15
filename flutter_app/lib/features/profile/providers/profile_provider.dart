import 'package:flutter/foundation.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/api_transport.dart';
import '../../admin/providers/admin_dashboard_provider.dart';
import '../../auth/domain/user.dart';
import '../../auth/providers/auth_provider.dart';

class ProfileProvider extends ChangeNotifier {
  ProfileProvider({
    required this.config,
    required this.apiClient,
    required this.transport,
    required this.authProvider,
    required this.adminProvider,
  }) {
    authProvider.addListener(_handleAuthChanged);
  }

  final AppConfig config;
  final ApiClient apiClient;
  final ApiTransport transport;
  final AuthProvider authProvider;
  final AdminDashboardProvider adminProvider;

  bool _isSavingProfile = false;
  String? _profileMessage;
  bool _profileMessageIsError = false;

  User? get currentUser => authProvider.currentUser;

  bool get isSavingProfile => _isSavingProfile;

  String? get profileMessage => _profileMessage;

  bool get profileMessageIsError => _profileMessageIsError;

  List<ProfileEndpoint> get endpoints => [
        ProfileEndpoint(label: 'App', uri: config.appBaseUri),
        ProfileEndpoint(label: 'Login', uri: apiClient.loginUri()),
        ProfileEndpoint(label: 'Current user', uri: apiClient.currentUserUri()),
        ProfileEndpoint(
          label: 'Update profile',
          uri: apiClient.currentUserUri(),
        ),
        ProfileEndpoint(
          label: 'Avatar upload',
          uri: apiClient.currentUserAvatarUri(),
        ),
        ProfileEndpoint(label: 'Media list', uri: apiClient.mediaListUri()),
        ProfileEndpoint(label: 'Upload init', uri: apiClient.uploadInitUri()),
        ProfileEndpoint(label: 'Albums', uri: apiClient.albumsUri()),
        ProfileEndpoint(label: 'Admin stats', uri: apiClient.adminStatsUri()),
        ProfileEndpoint(label: 'Progress socket', uri: config.websocketUri),
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
              'Flutter web now creates multipart upload sessions, streams parts directly to storage, inserts pending library items, and listens to /ws/progress for worker-side processing changes.',
          done: true,
        ),
        RolloutStep(
          title: 'Profile edits, comment writes, and owned album CRUD',
          description:
              'PATCH /users/me plus create/delete comment flows and owned album create, rename, description edits, and deletes are now wired into the live client.',
          done: true,
        ),
        RolloutStep(
          title:
              'Avatar upload, album sharing, native persistence, and admin controls',
          description:
              'The next production-grade gaps are PUT /users/me/avatar, album membership/sharing controls, secure mobile token storage, and admin user-management screens.',
          done: false,
        ),
      ];

  Future<bool> updateDisplayName(String value) async {
    final current = currentUser;
    final displayName = value.trim();

    if (current == null) {
      _setProfileMessage(
        'Sign in again before updating your profile.',
        isError: true,
      );
      return false;
    }
    if (displayName.isEmpty) {
      _setProfileMessage('Display name cannot be empty.', isError: true);
      return false;
    }
    if (displayName == current.displayName) {
      _setProfileMessage('Display name is already up to date.');
      return true;
    }

    _isSavingProfile = true;
    _profileMessage = null;
    notifyListeners();

    try {
      if (config.useDemoData) {
        authProvider.updateCurrentUser(
          current.copyWith(displayName: displayName),
        );
      } else {
        final response = await authProvider.withAuthorization(
          (headers) => transport.patchJson(
            apiClient.currentUserUri(),
            body: <String, String>{'display_name': displayName},
            headers: headers,
          ),
        );
        authProvider.updateCurrentUser(User.fromJson(response.asMap()));
      }

      _setProfileMessage('Profile saved.');
      return true;
    } on ApiException catch (error) {
      _setProfileMessage(error.message, isError: true);
      return false;
    } catch (_) {
      _setProfileMessage(
        'Unable to save your profile right now.',
        isError: true,
      );
      return false;
    } finally {
      _isSavingProfile = false;
      notifyListeners();
    }
  }

  void _handleAuthChanged() {
    notifyListeners();
  }

  void _setProfileMessage(String message, {bool isError = false}) {
    _profileMessage = message;
    _profileMessageIsError = isError;
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
