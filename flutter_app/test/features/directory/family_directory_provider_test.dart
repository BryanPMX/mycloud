import 'dart:convert';

import 'package:familycloud/core/config/app_config.dart';
import 'package:familycloud/core/network/api_client.dart';
import 'package:familycloud/core/network/api_transport.dart';
import 'package:familycloud/core/storage/secure_storage.dart';
import 'package:familycloud/features/auth/domain/user.dart';
import 'package:familycloud/features/auth/providers/auth_provider.dart';
import 'package:familycloud/features/directory/providers/family_directory_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  late AppConfig config;
  late ApiClient apiClient;
  late AuthProvider authProvider;
  late FamilyDirectoryProvider provider;
  late List<Uri> requestedUris;
  late ApiTransport transport;

  setUp(() {
    requestedUris = <Uri>[];
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
    transport = ApiTransport(
      client: MockClient((request) async {
        requestedUris.add(request.url);
        if (request.url.path.endsWith('/users/directory')) {
          return http.Response(
            jsonEncode(<String, Object?>{
              'users': <Map<String, Object?>>[
                <String, Object?>{
                  'id': 'user-1',
                  'display_name': 'Member One',
                  'avatar_url': null,
                },
                <String, Object?>{
                  'id': 'user-2',
                  'display_name': 'Member Two',
                  'avatar_url': 'https://signed.example/user-2-directory',
                },
              ],
            }),
            200,
            headers: const <String, String>{
              'content-type': 'application/json',
            },
          );
        }
        if (request.url.path.endsWith('/users/user-3/avatar')) {
          return http.Response(
            jsonEncode(<String, Object?>{
              'url': 'https://signed.example/user-3-avatar',
              'expires_at': '2026-03-15T19:00:00Z',
            }),
            200,
            headers: const <String, String>{
              'content-type': 'application/json',
            },
          );
        }

        return http.Response(
          jsonEncode(<String, Object?>{'error': 'not found'}),
          404,
          headers: const <String, String>{
            'content-type': 'application/json',
          },
        );
      }),
    );
    authProvider = AuthProvider(
      config: config,
      apiClient: apiClient,
      transport: transport,
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
        createdAt: DateTime.utc(2026, 3, 15),
      ),
    );
    provider = FamilyDirectoryProvider(
      config: config,
      apiClient: apiClient,
      transport: transport,
      authProvider: authProvider,
      avatarRefreshLeeway: Duration.zero,
    );
  });

  tearDown(() {
    provider.dispose();
    authProvider.dispose();
    transport.dispose();
  });

  test('load hydrates directory users and seeds avatar cache', () async {
    await provider.load();

    expect(provider.hasLoaded, isTrue);
    expect(provider.users, hasLength(2));
    expect(provider.users.last.displayName, 'Member Two');
    expect(
      provider.avatarUrlFor('user-2'),
      'https://signed.example/user-2-directory',
    );
    expect(requestedUris.single.path, '/api/v1/users/directory');
  });

  test('refreshAvatar requests the dedicated avatar-read endpoint', () async {
    await provider.refreshAvatar('user-3', force: true);

    expect(
      provider.avatarUrlFor('user-3'),
      'https://signed.example/user-3-avatar',
    );
    expect(requestedUris.single.path, '/api/v1/users/user-3/avatar');
    expect(requestedUris.single.queryParameters['ttl'], '300');
  });
}
