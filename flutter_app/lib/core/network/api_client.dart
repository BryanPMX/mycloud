import '../config/app_config.dart';

class ApiClient {
  const ApiClient(this.config);

  final AppConfig config;

  Uri loginUri() => endpoint('/auth/login');

  Uri refreshUri() => endpoint('/auth/refresh');

  Uri logoutUri() => endpoint('/auth/logout');

  Uri acceptInviteUri() => endpoint('/auth/invite/accept');

  Uri currentUserUri() => endpoint('/users/me');

  Uri currentUserAvatarUri() => endpoint('/users/me/avatar');

  Uri mediaListUri() => endpoint('/media');

  Uri mediaDetailUri(String mediaId) => endpoint('/media/$mediaId');

  Uri mediaSearchUri(String query) =>
      endpoint('/media/search', queryParameters: {'q': query});

  Uri mediaThumbUri(
    String mediaId, {
    String size = 'medium',
    int ttlSeconds = 300,
  }) {
    return endpoint(
      '/media/$mediaId/thumb',
      queryParameters: {'size': size, 'ttl': '$ttlSeconds'},
    );
  }

  Uri mediaDownloadUri(String mediaId, {int ttlSeconds = 3600}) {
    return endpoint(
      '/media/$mediaId/url',
      queryParameters: {'ttl': '$ttlSeconds'},
    );
  }

  Uri albumsUri() => endpoint('/albums');

  Uri albumDetailUri(String albumId) => endpoint('/albums/$albumId');

  Uri albumMediaUri(String albumId) => endpoint('/albums/$albumId/media');

  Uri adminStatsUri() => endpoint('/admin/stats');

  Uri adminUsersUri() => endpoint('/admin/users');

  Uri mediaCommentsUri(String mediaId) => endpoint('/media/$mediaId/comments');

  Uri mediaCommentUri(String mediaId, String commentId) =>
      endpoint('/media/$mediaId/comments/$commentId');

  Uri favoriteMediaUri(String mediaId) => endpoint('/media/$mediaId/favorite');

  Uri uploadInitUri() => endpoint('/media/upload/init');

  Uri uploadPartUri(String mediaId) =>
      endpoint('/media/upload/$mediaId/part-url');

  Uri uploadCompleteUri(String mediaId) =>
      endpoint('/media/upload/$mediaId/complete');

  Uri abortUploadUri(String mediaId) => endpoint('/media/upload/$mediaId');

  Uri endpoint(String path, {Map<String, String>? queryParameters}) {
    final cleanedPath = path.startsWith('/') ? path.substring(1) : path;
    final baseSegments = config.apiBaseUri.pathSegments
        .where((segment) => segment.isNotEmpty)
        .toList(growable: true);
    final extraSegments =
        cleanedPath.split('/').where((segment) => segment.isNotEmpty);

    return config.apiBaseUri.replace(
      pathSegments: [...baseSegments, ...extraSegments],
      queryParameters: queryParameters == null || queryParameters.isEmpty
          ? null
          : queryParameters,
    );
  }
}
