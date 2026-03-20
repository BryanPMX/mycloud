import 'package:familycloud/core/config/app_config.dart';
import 'package:familycloud/core/connectivity/connectivity_service.dart';
import 'package:familycloud/core/network/api_client.dart';
import 'package:familycloud/core/network/api_transport.dart';
import 'package:familycloud/core/storage/secure_storage.dart';
import 'package:familycloud/features/auth/domain/user.dart';
import 'package:familycloud/features/auth/providers/auth_provider.dart';
import 'package:familycloud/features/comments/providers/comment_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';

void main() {
  late AppConfig config;
  late ApiClient apiClient;
  late ConnectivityService connectivityService;
  late AuthProvider authProvider;
  late CommentProvider provider;

  setUp(() {
    config = AppConfig(
      appName: 'Mynube',
      appBaseUri: Uri(scheme: 'https', host: 'mynube.live'),
      apiBaseUri: Uri(
        scheme: 'https',
        host: 'api.mynube.live',
        path: '/api/v1',
      ),
      websocketUri: Uri(
        scheme: 'wss',
        host: 'api.mynube.live',
        path: '/ws/progress',
      ),
      environmentLabel: 'test',
      useDemoData: false,
    );
    apiClient = ApiClient(config);
    connectivityService = ConnectivityService(
      initialPlatformOnline: true,
      registerPlatformListener: (_) => null,
    )..markUnreachable('Backend offline for test.');
    authProvider = AuthProvider(
      config: config,
      apiClient: apiClient,
      transport: ApiTransport(client: MockClient((_) async {
        throw StateError('Network should not be hit while offline.');
      })),
      secureStorage: SecureStorage(),
    );
    authProvider.updateCurrentUser(
      User(
        id: 'user-1',
        email: 'member@mynube.live',
        displayName: 'Member One',
        role: UserRole.member,
        storageUsed: 1024,
        quotaBytes: 2048,
        createdAt: DateTime.utc(2026, 3, 20),
      ),
    );
    provider = CommentProvider(
      config: config,
      apiClient: apiClient,
      transport: ApiTransport(client: MockClient((_) async {
        throw StateError('Network should not be hit while offline.');
      })),
      authProvider: authProvider,
      connectivityService: connectivityService,
    );
  });

  tearDown(() {
    provider.dispose();
    authProvider.dispose();
    connectivityService.dispose();
  });

  test(
      'offline addComment surfaces the connectivity message without calling the API',
      () async {
    final didPost = await provider.addComment('media-1', 'Still there?');

    expect(didPost, isFalse);
    expect(provider.errorMessage, 'Backend offline for test.');
  });
}
