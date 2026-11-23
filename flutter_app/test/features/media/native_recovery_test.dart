import 'dart:async';
import 'dart:typed_data';

import 'package:familycloud/core/config/app_config.dart';
import 'package:familycloud/core/connectivity/connectivity_service.dart';
import 'package:familycloud/core/network/api_client.dart';
import 'package:familycloud/core/network/api_transport.dart';
import 'package:familycloud/core/storage/secure_storage.dart';
import 'package:familycloud/features/admin/providers/admin_dashboard_provider.dart';
import 'package:familycloud/features/auth/domain/user.dart';
import 'package:familycloud/features/auth/providers/auth_provider.dart';
import 'package:familycloud/features/media/data/selected_upload_file.dart';
import 'package:familycloud/features/media/providers/media_list_provider.dart';
import 'package:familycloud/features/media/providers/media_upload_provider.dart';
import 'package:familycloud/features/profile/providers/profile_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';

import '../../shared/memory_selected_upload_file.dart';

User _user(String id) => User(
    id: id,
    email: '$id@validation.invalid',
    displayName: id,
    role: UserRole.member,
    storageUsed: 0,
    quotaBytes: 1 << 30,
    createdAt: DateTime.utc(2026));

void main() {
  late MediaUploadProvider uploads;
  late ProfileProvider profile;
  late AuthProvider auth;
  late Completer<List<SelectedUploadFile>> recovered;
  late Completer<SelectedUploadFile?> recoveredAvatar;
  late List<Completer<List<SelectedUploadFile>>> picks;
  late SelectedUploadFile file;
  int requests = 0;

  setUp(() {
    requests = 0;
    recovered = Completer();
    recoveredAvatar = Completer();
    picks = [Completer(), Completer()];
    var pickIndex = 0;
    file = MemorySelectedUploadFile(
        name: 'synthetic.png',
        mimeType: 'image/png',
        bytes: Uint8List.fromList([1, 2, 3]));
    final config = AppConfig(
        appName: 'Test',
        appBaseUri: Uri.parse('https://validation.invalid'),
        apiBaseUri: Uri.parse('https://validation.invalid/api/v1'),
        websocketUri: Uri.parse('wss://validation.invalid/ws'),
        environmentLabel: 'test',
        useDemoData: false);
    final api = ApiClient(config);
    final transport = ApiTransport(client: MockClient((_) async {
      requests++;
      throw StateError('Recovery must not make API requests');
    }));
    auth = AuthProvider(
        config: config,
        apiClient: api,
        transport: transport,
        secureStorage: SecureStorage())
      ..updateCurrentUser(_user('first'));
    final connectivity = ConnectivityService(initialPlatformOnline: true);
    final media = MediaListProvider(
        config: config,
        apiClient: api,
        transport: transport,
        authProvider: auth,
        connectivityService: connectivity);
    final admin = AdminDashboardProvider(
        config: config,
        apiClient: api,
        transport: transport,
        authProvider: auth);
    uploads = MediaUploadProvider(
        config: config,
        apiClient: api,
        transport: transport,
        authProvider: auth,
        mediaProvider: media,
        connectivityService: connectivity,
        lostUploadFilesRetriever: () => recovered.future,
        uploadFilesPicker: () => picks[pickIndex++].future);
    profile = ProfileProvider(
        config: config,
        apiClient: api,
        transport: transport,
        authProvider: auth,
        adminProvider: admin,
        connectivityService: connectivity,
        lostAvatarFileRetriever: () => recoveredAvatar.future);
    addTearDown(() {
      profile.dispose();
      uploads.dispose();
      media.dispose();
      admin.dispose();
      auth.dispose();
      transport.dispose();
      connectivity.dispose();
    });
  });

  test(
      'unowned recovered media requires reselection and never starts uploading',
      () async {
    final pending = uploads.recoverLostFiles();
    recovered.complete([file]);
    await pending;
    expect(uploads.tasks, isEmpty);
    expect(
        uploads.errorMessage, contains('Choose those photos or videos again'));
    expect(requests, 0);
  });

  test('late picker recovery cannot affect a different account', () async {
    final pending = uploads.recoverLostFiles();
    uploads.reset();
    auth.updateCurrentUser(_user('second'));
    recovered.complete([file]);
    await pending;
    expect(uploads.tasks, isEmpty);
    expect(uploads.errorMessage, isNull);
    expect(requests, 0);
  });

  test('an old picker failure cannot clear a new account picker state',
      () async {
    final first = uploads.pickAndUpload();
    uploads.reset();
    auth.updateCurrentUser(_user('second'));
    final second = uploads.pickAndUpload();
    picks[0].completeError(StateError('Old picker failed'));
    await first;
    expect(uploads.isPickingFiles, isTrue);
    expect(uploads.errorMessage, isNull);
    picks[1].complete([]);
    await second;
    expect(uploads.isPickingFiles, isFalse);
    expect(requests, 0);
  });

  test('lost media cannot silently become a profile photo', () async {
    final pending = profile.recoverLostAvatarUpload();
    recoveredAvatar.complete(file);
    await pending;
    expect(profile.profileMessage, contains('Choose your profile photo again'));
    expect(profile.isUploadingAvatar, isFalse);
    expect(requests, 0);
  });

  test('late avatar recovery cannot affect a different account', () async {
    final pending = profile.recoverLostAvatarUpload();
    auth.updateCurrentUser(_user('second'));
    recoveredAvatar.complete(file);
    await pending;
    expect(profile.profileMessage, isNull);
    expect(requests, 0);
  });
}
