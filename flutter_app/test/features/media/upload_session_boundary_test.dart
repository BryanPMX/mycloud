import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:familycloud/core/config/app_config.dart';
import 'package:familycloud/core/connectivity/connectivity_service.dart';
import 'package:familycloud/core/network/api_client.dart';
import 'package:familycloud/core/network/api_exception.dart';
import 'package:familycloud/core/network/api_transport.dart';
import 'package:familycloud/core/storage/secure_storage.dart';
import 'package:familycloud/features/auth/domain/user.dart';
import 'package:familycloud/features/auth/providers/auth_provider.dart';
import 'package:familycloud/features/media/providers/media_list_provider.dart';
import 'package:familycloud/features/media/providers/media_upload_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import '../../shared/memory_selected_upload_file.dart';

class _MemoryStorage extends SecureStorage {
  @override
  bool get supportsSecurePersistence => false;
}

User user(String id) => User(
    id: id,
    email: '$id@validation.invalid',
    displayName: id,
    role: UserRole.member,
    storageUsed: 0,
    quotaBytes: 1 << 30,
    createdAt: DateTime.utc(2026));
final config = AppConfig(
    appName: 'Validation',
    appBaseUri: Uri.parse('https://validation.invalid'),
    apiBaseUri: Uri.parse('https://validation.invalid/api/v1'),
    websocketUri: Uri.parse('wss://validation.invalid/ws/progress'),
    environmentLabel: 'test',
    useDemoData: false);
void main() {
  test('queued files never continue under a different account', () async {
    final started = Completer<void>();
    final response = Completer<http.Response>();
    final paths = <String>[];
    final transport = ApiTransport(client: MockClient((request) async {
      paths.add(request.url.path);
      if (!started.isCompleted) {
        started.complete();
      }
      return response.future;
    }));
    final auth = AuthProvider(
        config: config,
        apiClient: ApiClient(config),
        transport: transport,
        secureStorage: _MemoryStorage())
      ..updateCurrentUser(user('first'));
    final connectivity = ConnectivityService(initialPlatformOnline: true);
    final media = MediaListProvider(
        config: config,
        apiClient: ApiClient(config),
        transport: transport,
        authProvider: auth,
        connectivityService: connectivity);
    final uploads = MediaUploadProvider(
        config: config,
        apiClient: ApiClient(config),
        transport: transport,
        authProvider: auth,
        mediaProvider: media,
        connectivityService: connectivity);
    final file = MemorySelectedUploadFile(
        name: 'private.png',
        mimeType: 'image/png',
        bytes: Uint8List.fromList([1, 2, 3]));
    await uploads.queueUploads([file, file, file]);
    await started.future;
    expect(paths,
        hasLength(1)); // Serial dispatch bounds memory and active requests.
    uploads.reset();
    auth.updateCurrentUser(user('second'));
    response.complete(http.Response(
        jsonEncode({
          'media_id': 'old-asset',
          'upload_id': 'old-upload',
          'part_size_bytes': 5242880,
          'part_url_ttl': 900
        }),
        201));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(paths, hasLength(1));
    expect(uploads.tasks, isEmpty);
    uploads.dispose();
    media.dispose();
    auth.dispose();
    transport.dispose();
    connectivity.dispose();
  });
  test('a transient refresh failure preserves the current account', () async {
    final transport = ApiTransport(
        client: MockClient((request) async => http.Response(
            '{}', request.url.path.endsWith('/auth/refresh') ? 503 : 401)));
    final auth = AuthProvider(
        config: config,
        apiClient: ApiClient(config),
        transport: transport,
        secureStorage: _MemoryStorage())
      ..updateCurrentUser(user('first'));
    await expectLater(
        auth.withAuthorization((headers) => transport.get(
            Uri.parse('https://validation.invalid/protected'),
            headers: headers)),
        throwsA(
            isA<ApiException>().having((e) => e.statusCode, 'status', 503)));
    expect(auth.isAuthenticated, isTrue);
    expect(auth.currentUser?.id, 'first');
    auth.dispose();
    transport.dispose();
  });
}
