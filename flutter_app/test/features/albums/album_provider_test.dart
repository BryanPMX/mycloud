import 'package:familycloud/core/config/app_config.dart';
import 'package:familycloud/core/network/api_client.dart';
import 'package:familycloud/core/network/api_transport.dart';
import 'package:familycloud/core/storage/secure_storage.dart';
import 'package:familycloud/features/albums/domain/album_share.dart';
import 'package:familycloud/features/albums/providers/album_provider.dart';
import 'package:familycloud/features/auth/providers/auth_provider.dart';
import 'package:familycloud/features/media/providers/media_list_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppConfig config;
  late ApiTransport transport;
  late ApiClient apiClient;
  late AuthProvider authProvider;
  late MediaListProvider mediaProvider;
  late AlbumProvider albumProvider;

  setUp(() async {
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
      useDemoData: true,
    );
    transport = ApiTransport();
    apiClient = ApiClient(config);
    authProvider = AuthProvider(
      config: config,
      apiClient: apiClient,
      transport: transport,
      secureStorage: SecureStorage(),
    );
    await authProvider.signInAsDemoAdmin();
    mediaProvider = MediaListProvider(
      config: config,
      apiClient: apiClient,
      transport: transport,
      authProvider: authProvider,
    );
    albumProvider = AlbumProvider(
      config: config,
      apiClient: apiClient,
      transport: transport,
      authProvider: authProvider,
    );
  });

  tearDown(() {
    albumProvider.dispose();
    mediaProvider.dispose();
    authProvider.dispose();
    transport.dispose();
  });

  test('adds demo media into an album and updates the count', () async {
    final startingItems = albumProvider.mediaForAlbum('album-1');
    final candidate = mediaProvider.allItems.firstWhere(
      (media) =>
          media.ownerId == 'user-member' &&
          startingItems.every((existing) => existing.id != media.id),
    );

    final added = await albumProvider.addMediaToAlbum(
      albumId: 'album-1',
      media: [candidate],
    );

    final updatedAlbum =
        albumProvider.ownedAlbums.firstWhere((album) => album.id == 'album-1');
    expect(added, isTrue);
    expect(
      albumProvider
          .mediaForAlbum('album-1')
          .any((media) => media.id == candidate.id),
      isTrue,
    );
    expect(updatedAlbum.mediaCount, 3);
  });

  test('creates a demo family share for an album', () async {
    final created = await albumProvider.createShare(
      albumId: 'album-1',
      permission: AlbumPermission.view,
    );

    expect(created, isTrue);
    expect(albumProvider.sharesForAlbum('album-1'), isNotEmpty);
    expect(albumProvider.sharesForAlbum('album-1').first.isFamilyShare, isTrue);
  });
}
