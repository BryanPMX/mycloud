import 'package:flutter/foundation.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/api_transport.dart';
import '../../admin/providers/admin_dashboard_provider.dart';
import '../../auth/domain/user.dart';
import '../../auth/providers/auth_provider.dart';
import '../data/avatar_picker.dart';

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

  static const int maxAvatarBytes = 5 * 1024 * 1024;

  final AppConfig config;
  final ApiClient apiClient;
  final ApiTransport transport;
  final AuthProvider authProvider;
  final AdminDashboardProvider adminProvider;

  bool _isSavingProfile = false;
  bool _isUploadingAvatar = false;
  String? _profileMessage;
  bool _profileMessageIsError = false;

  User? get currentUser => authProvider.currentUser;

  bool get isSavingProfile => _isSavingProfile;

  bool get isUploadingAvatar => _isUploadingAvatar;

  String? get profileMessage => _profileMessage;

  bool get profileMessageIsError => _profileMessageIsError;

  bool get canPickAvatar => config.useDemoData || supportsAvatarPicking;

  String get avatarPickerHint {
    if (config.useDemoData) {
      return 'Demo mode simulates avatar updates without device file access.';
    }
    if (!supportsAvatarPicking) {
      return 'Avatar file picking is currently implemented for Flutter web only.';
    }
    return 'Choose a JPG, PNG, WEBP, or HEIC image under 5 MB.';
  }

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
          title: 'Profile, album, and admin mutation coverage',
          description:
              'Display-name edits, avatar uploads, album media membership and sharing flows, secure native token persistence, and admin user-management controls are now wired into the Flutter client.',
          done: true,
        ),
        RolloutStep(
          title: 'Remaining polish',
          description:
              'The main follow-up is broader mobile media picking/offline polish plus a non-admin family-directory endpoint so album owners can choose individual recipients without relying on admin-only user listing.',
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
        final updatedUser = current.copyWith(displayName: displayName);
        authProvider.updateCurrentUser(updatedUser);
        adminProvider.reconcileCurrentUser(updatedUser);
      } else {
        final response = await authProvider.withAuthorization(
          (headers) => transport.patchJson(
            apiClient.currentUserUri(),
            body: <String, String>{'display_name': displayName},
            headers: headers,
          ),
        );
        final updatedUser = User.fromJson(response.asMap());
        authProvider.updateCurrentUser(updatedUser);
        adminProvider.reconcileCurrentUser(updatedUser);
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

  Future<bool> pickAndUploadAvatar() async {
    final current = currentUser;
    if (current == null) {
      _setProfileMessage(
        'Sign in again before uploading an avatar.',
        isError: true,
      );
      notifyListeners();
      return false;
    }

    _isUploadingAvatar = true;
    _profileMessage = null;
    notifyListeners();

    try {
      if (config.useDemoData) {
        final updatedUser = current.copyWith(
          avatarUrl:
              'users/${current.id}/avatar-${DateTime.now().toUtc().millisecondsSinceEpoch}.png',
        );
        authProvider.updateCurrentUser(updatedUser);
        _setProfileMessage('Avatar saved.');
        return true;
      }

      final file = await pickAvatarFile();
      if (file == null) {
        _setProfileMessage('Avatar selection cancelled.');
        return false;
      }
      if (!file.mimeType.startsWith('image/')) {
        _setProfileMessage('Choose an image file for the avatar.',
            isError: true);
        return false;
      }
      if (file.sizeBytes <= 0 || file.sizeBytes > maxAvatarBytes) {
        _setProfileMessage('Avatar images must be smaller than 5 MB.',
            isError: true);
        return false;
      }

      final bytes = await file.readChunk(0, file.sizeBytes);
      final response = await authProvider.withAuthorization(
        (headers) => transport.putBytes(
          apiClient.currentUserAvatarUri(),
          headers: <String, String>{
            ...headers,
            'Accept': 'application/json',
            'Content-Type': file.mimeType,
          },
          body: bytes,
        ),
      );
      final payload = response.asMap();
      final avatarUrl = payload['avatar_url'] as String?;
      authProvider.updateCurrentUser(current.copyWith(avatarUrl: avatarUrl));
      _setProfileMessage('Avatar saved.');
      return true;
    } on UnsupportedError catch (error) {
      _setProfileMessage(
        error.message ?? 'Avatar picking is not available on this platform.',
        isError: true,
      );
      return false;
    } on ApiException catch (error) {
      _setProfileMessage(error.message, isError: true);
      return false;
    } catch (_) {
      _setProfileMessage(
        'Unable to upload your avatar right now.',
        isError: true,
      );
      return false;
    } finally {
      _isUploadingAvatar = false;
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
