import '../../../core/network/api_client.dart';
import '../../../core/network/api_transport.dart';
import '../../auth/providers/auth_provider.dart';
import '../domain/media.dart';

class TrashPage {
  const TrashPage(this.items, this.nextCursor);
  final List<Media> items;
  final String nextCursor;
}

class MediaRepository {
  const MediaRepository(
      {required this.api, required this.transport, required this.auth});
  final ApiClient api;
  final ApiTransport transport;
  final AuthProvider auth;
  Future<TrashPage> trash({String cursor = ''}) async {
    final response = await auth.withAuthorization((headers) => transport.get(
        api.endpoint('/media/trash', queryParameters: {
          'limit': '50',
          if (cursor.isNotEmpty) 'cursor': cursor
        }),
        headers: headers));
    final payload = response.asMap();
    return TrashPage(
        (payload['items'] as List<dynamic>)
            .map((m) => Media.fromJson(m as Map<String, dynamic>))
            .toList(),
        payload['next_cursor'] as String? ?? '');
  }

  Future<void> moveToTrash(String id) async {
    await auth.withAuthorization((headers) =>
        transport.delete(api.endpoint('/media/$id'), headers: headers));
  }

  Future<void> restore(String id) async {
    await auth.withAuthorization((headers) => transport
        .postJson(api.endpoint('/media/$id/restore'), headers: headers));
  }

  Future<void> deletePermanently(String id) async {
    await auth.withAuthorization((headers) => transport
        .delete(api.endpoint('/media/$id/permanent'), headers: headers));
  }

  Future<void> emptyTrash() async {
    await auth.withAuthorization((headers) =>
        transport.delete(api.endpoint('/media/trash'), headers: headers));
  }
}
