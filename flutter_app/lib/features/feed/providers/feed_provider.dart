import 'package:flutter/foundation.dart';
import '../../../core/config/demo_assets.dart';
import '../../../core/config/app_config.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/api_transport.dart';
import '../../../core/network/signed_url_cache.dart';
import '../../auth/providers/auth_provider.dart';
import '../domain/family.dart';
import '../../media/domain/media.dart';
import '../../media/data/media_repository.dart';

class FeedProvider extends ChangeNotifier {
  FeedProvider(
      {required this.config,
      required this.api,
      required this.transport,
      required this.auth}) {
    mediaRepository =
        MediaRepository(api: api, transport: transport, auth: auth);
    auth.addListener(_authChanged);
    _authChanged();
  }
  late final MediaRepository mediaRepository;
  final AppConfig config;
  final ApiClient api;
  final ApiTransport transport;
  final AuthProvider auth;
  List<Family> families = [];
  List<FamilyPost> posts = [];
  Family? selected;
  String? error;
  bool loading = false;
  bool mutating = false;
  String _nextCursor = '';
  int _generation = 0;
  String? _userId;
  bool _disposed = false;
  final _previews = SignedUrlCache(refreshLeeway: const Duration(seconds: 30));
  bool get hasMore => _nextCursor.isNotEmpty;
  void _emit() {
    if (!_disposed) notifyListeners();
  }

  void _authChanged() {
    final next = auth.currentUser?.id;
    if (next == _userId) return;
    _userId = next;
    _generation++;
    families = [];
    posts = [];
    selected = null;
    error = null;
    loading = false;
    _nextCursor = '';
    _previews.clear();
    _emit();
  }

  Future<void> loadFamilies() async {
    final generation = _generation;
    loading = true;
    error = null;
    _emit();
    try {
      final response = config.useDemoData
          ? null
          : await auth.withAuthorization((headers) =>
              transport.get(api.endpoint('/families'), headers: headers));
      if (generation != _generation) return;
      families = config.useDemoData
          ? [const Family(id: 'demo-family', name: 'Our family', role: 'owner')]
          : (response!.asMap()['families'] as List<dynamic>)
              .map((item) => Family.fromJson(item as Map<String, dynamic>))
              .toList();
      selected =
          families.where((item) => item.id == selected?.id).firstOrNull ??
              families.firstOrNull;
      posts = [];
      _nextCursor = '';
      _previews.clear();
      if (selected != null) await loadPosts();
    } on ApiException catch (e) {
      if (generation == _generation) error = e.message;
    } catch (_) {
      if (generation == _generation) {
        error = 'Unable to load your families. Try again.';
      }
    } finally {
      if (generation == _generation) {
        loading = false;
        _emit();
      }
    }
  }

  Future<void> selectFamily(Family family) async {
    _generation++;
    selected = family;
    posts = [];
    error = null;
    _nextCursor = '';
    _previews.clear();
    await loadPosts();
  }

  Future<void> loadPosts({bool more = false}) async {
    final family = selected;
    if (family == null) return;
    final generation = _generation;
    loading = true;
    error = null;
    _emit();
    try {
      if (config.useDemoData) {
        posts = [
          for (var i = 0; i < 2; i++)
            FamilyPost(
                id: 'demo-post-$i',
                authorId: i == 0 ? 'user-member' : 'user-admin',
                authorName: i == 0 ? 'Sofia' : 'Alex',
                caption: i == 0
                    ? 'Taking the long way home. Always worth it.'
                    : 'A few little things from this weekend. Wish you were here.',
                createdAt: DateTime.now().subtract(Duration(hours: i * 5 + 1)),
                media: [
                  for (final n in (i == 0 ? [1, 5] : [4, 6, 9]))
                    Media(
                        id: 'media-$n',
                        ownerId: i == 0 ? 'user-member' : 'user-admin',
                        filename: 'A little moment.jpg',
                        mimeType: 'image/jpeg',
                        sizeBytes: 3000000,
                        width: 900,
                        height: 1100,
                        durationSecs: 0,
                        status: MediaStatus.ready,
                        isFavorite: false,
                        thumbUrls: const ThumbUrls(),
                        uploadedAt: DateTime.now())
                ])
        ];
        return;
      }
      final response = await auth.withAuthorization((headers) => transport.get(
          api.endpoint('/families/${family.id}/posts',
              queryParameters: {if (more) 'cursor': _nextCursor}),
          headers: headers));
      if (generation != _generation) return;
      final payload = response.asMap();
      final next = (payload['posts'] as List<dynamic>)
          .map((item) => FamilyPost.fromJson(item as Map<String, dynamic>))
          .toList();
      posts = more ? [...posts, ...next] : next;
      _nextCursor = payload['next_cursor'] as String? ?? '';
    } on ApiException catch (e) {
      if (generation == _generation) {
        error = e.message;
        if (e.statusCode == 403 || e.statusCode == 404) {
          posts = [];
          _previews.clear();
        }
      }
    } catch (_) {
      if (generation == _generation) {
        error = 'Unable to load the feed. Try again.';
      }
    } finally {
      if (generation == _generation) {
        loading = false;
        _emit();
      }
    }
  }

  Future<void> createFamily(String name) async {
    await auth.withAuthorization((headers) => transport.postJson(
        api.endpoint('/families'),
        body: {'name': name},
        headers: headers));
    await loadFamilies();
  }

  Future<void> acceptInvitation(String token) async {
    await auth.withAuthorization((headers) => transport.postJson(
        api.endpoint('/families/invitations/accept'),
        body: {'token': token.trim()},
        headers: headers));
    await loadFamilies();
  }

  Future<String> invite(String email) async {
    final response = await auth.withAuthorization((headers) => transport
        .postJson(api.endpoint('/families/${selected!.id}/invitations'),
            body: {'email': email}, headers: headers));
    return response.asMap()['token'] as String;
  }

  Future<List<Map<String, dynamic>>> members() async {
    final response = await auth.withAuthorization((headers) => transport.get(
        api.endpoint('/families/${selected!.id}/members'),
        headers: headers));
    return (response.asMap()['members'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
  }

  Future<void> removeMember(String id) async {
    await auth.withAuthorization((headers) => transport.delete(
        api.endpoint('/families/${selected!.id}/members/$id'),
        headers: headers));
    await loadFamilies();
  }

  Future<void> publish(String caption, List<String> ids,
      {String? familyID}) async {
    if (mutating) return;
    final family = familyID == null
        ? selected
        : families.where((f) => f.id == familyID).firstOrNull;
    if (family == null || ids.isEmpty || ids.length > 20) return;
    mutating = true;
    _emit();
    try {
      await auth.withAuthorization((headers) => transport.postJson(
          api.endpoint('/families/${family.id}/posts'),
          body: {'caption': caption, 'media_ids': ids},
          headers: headers));
      if (selected?.id == family.id) await loadPosts();
    } finally {
      mutating = false;
      _emit();
    }
  }

  Future<void> unshare(String id) async {
    await auth.withAuthorization((headers) => transport.delete(
        api.endpoint('/families/${selected!.id}/posts/$id'),
        headers: headers));
    await loadPosts();
  }

  Future<String> preview(String id, {String size = 'medium'}) async {
    if (config.useDemoData) return demoMemoryAsset(id);
    final cacheKey = '$id:$size';
    final generation = _generation;
    if (!_previews.needsRefresh(cacheKey)) return _previews.urlFor(cacheKey)!;
    final response = await auth.withAuthorization((headers) =>
        transport.get(api.mediaThumbUri(id, size: size), headers: headers));
    if (generation != _generation) throw StateError('Session changed');
    final payload = response.asMap();
    final url = payload['url'] as String;
    _previews.remember(cacheKey, url,
        expiresAt: DateTime.parse(payload['expires_at'] as String));
    return url;
  }

  Future<String> original(String id) async {
    if (config.useDemoData) return demoMemoryAsset(id);
    final generation = _generation;
    final response = await auth.withAuthorization((headers) => transport
        .get(api.mediaDownloadUri(id, ttlSeconds: 900), headers: headers));
    if (generation != _generation) throw StateError('Session changed');
    return response.asMap()['url'] as String;
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    auth.removeListener(_authChanged);
    _previews.clear();
    super.dispose();
  }
}
