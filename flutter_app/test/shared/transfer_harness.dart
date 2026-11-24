import 'dart:async';
import 'dart:convert';
import 'package:familycloud/core/config/app_config.dart';
import 'package:familycloud/core/connectivity/connectivity_service.dart';
import 'package:familycloud/core/network/api_client.dart';
import 'package:familycloud/core/network/api_transport.dart';
import 'package:familycloud/core/storage/secure_storage.dart';
import 'package:familycloud/features/auth/domain/user.dart';
import 'package:familycloud/features/auth/providers/auth_provider.dart';
import 'package:familycloud/features/media/data/transfers/part_transfer.dart';
import 'package:familycloud/features/media/data/transfers/upload_checkpoint.dart';
import 'package:familycloud/features/media/data/transfers/upload_journal.dart';
import 'package:familycloud/features/media/domain/upload_task.dart';
import 'package:familycloud/features/media/providers/media_list_provider.dart';
import 'package:familycloud/features/media/providers/media_upload_provider.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

User transferUser(String id) => User(
    id: id,
    email: '$id@validation.invalid',
    displayName: id,
    role: UserRole.member,
    storageUsed: 0,
    quotaBytes: 1 << 30,
    createdAt: DateTime.utc(2026));

class FakePartTransfer implements PartTransfer {
  final List<int> calls = [];
  Future<String> Function(UploadCheckpoint, int)? onPart;
  @override
  bool get background => false;
  @override
  Future<String> upload(
      UploadCheckpoint cp, int number, Uri url, int start, int end) async {
    calls.add(number);
    return onPart == null ? 'etag-$number' : await onPart!(cp, number);
  }

  @override
  Future<void> cancelOwner(String owner) async {}
  @override
  Future<void> prepareOwner(String owner) async {}
  @override
  Future<void> cancel(UploadCheckpoint cp) async {}
}

class TransferHarness {
  TransferHarness({UploadJournal? journal, this.partSize = 3, this.onRequest}) {
    config = AppConfig(
        appName: 'Validation',
        appBaseUri: Uri.parse('https://validation.invalid'),
        apiBaseUri: Uri.parse('https://validation.invalid/api/v1'),
        websocketUri: Uri.parse('wss://validation.invalid/ws'),
        environmentLabel: 'test',
        useDemoData: false,
        enableResumableUploads: true,
        enableDeviceBackup: true);
    transport = ApiTransport(client: MockClient((request) async {
      requests.add(request);
      final override = await onRequest?.call(request);
      if (override != null) return override;
      final path = request.url.path;
      if (path.endsWith('/upload/init')) {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        mediaId = body['client_upload_id'] as String;
        size = body['size_bytes'] as int;
        return http.Response(
            jsonEncode({
              'media_id': mediaId,
              'upload_id': 'synthetic-upload',
              'part_size_bytes': partSize
            }),
            201);
      }
      if (path.endsWith('/part-url')) {
        return http.Response(
            jsonEncode({'url': 'https://objects.validation.invalid/part'}),
            200);
      }
      if (path.endsWith('/complete')) {
        return http.Response(
            jsonEncode({
              'id': mediaId,
              'filename': 'synthetic.png',
              'size_bytes': size
            }),
            200);
      }
      if (request.method == 'DELETE') return http.Response('', 204);
      if (path.endsWith('/media/$mediaId')) {
        return http.Response(
            jsonEncode({'id': mediaId, 'status': 'ready'}), 200);
      }
      if (path.endsWith('/media') || path.endsWith('/media/search')) {
        return http.Response('{"items":[],"next_cursor":""}', 200);
      }
      throw StateError('Unexpected synthetic API request');
    }));
    api = ApiClient(config);
    auth = AuthProvider(
        config: config,
        apiClient: api,
        transport: transport,
        secureStorage: SecureStorage())
      ..updateCurrentUser(transferUser('first'));
    connectivity = ConnectivityService(initialPlatformOnline: true);
    media = MediaListProvider(
        config: config,
        apiClient: api,
        transport: transport,
        authProvider: auth,
        connectivityService: connectivity);
    uploads = MediaUploadProvider(
        config: config,
        apiClient: api,
        transport: transport,
        authProvider: auth,
        mediaProvider: media,
        connectivityService: connectivity,
        uploadJournal: journal,
        partTransfer: parts);
  }
  final int partSize;
  final Future<http.Response?> Function(http.Request)? onRequest;
  final FakePartTransfer parts = FakePartTransfer();
  final List<http.Request> requests = [];
  late AppConfig config;
  late ApiClient api;
  late ApiTransport transport;
  late AuthProvider auth;
  late ConnectivityService connectivity;
  late MediaListProvider media;
  late MediaUploadProvider uploads;
  String mediaId = '';
  int size = 0;
  Future<void> waitForStage(MediaUploadStage stage) async {
    final deadline = DateTime.now().add(const Duration(seconds: 3));
    while (DateTime.now().isBefore(deadline)) {
      if (uploads.tasks.any((t) => t.stage == stage)) return;
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    throw StateError(
        'Upload did not reach ${stage.name}: ${uploads.tasks.map((t) => t.message)}');
  }

  void dispose() {
    uploads.dispose();
    media.dispose();
    auth.dispose();
    transport.dispose();
    connectivity.dispose();
  }
}
