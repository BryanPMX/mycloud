import 'package:flutter/foundation.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/api_transport.dart';
import '../../auth/providers/auth_provider.dart';
import '../domain/comment.dart';

class CommentProvider extends ChangeNotifier {
  CommentProvider({
    required AppConfig config,
    required ApiClient apiClient,
    required ApiTransport transport,
    required AuthProvider authProvider,
  })  : _config = config,
        _apiClient = apiClient,
        _transport = transport,
        _authProvider = authProvider;

  final AppConfig _config;
  final ApiClient _apiClient;
  final ApiTransport _transport;
  final AuthProvider _authProvider;

  static final Map<String, List<Comment>> _seedCommentsByMediaId =
      <String, List<Comment>>{
    'media-1': <Comment>[
      Comment(
        id: 'comment-1',
        author: const CommentAuthor(
          id: 'user-admin',
          displayName: 'Admin Operator',
        ),
        body:
            'This is a strong candidate for the library hero tile once live thumbs land.',
        createdAt: DateTime.utc(2026, 3, 14, 16, 12),
      ),
      Comment(
        id: 'comment-2',
        author: const CommentAuthor(
          id: 'user-member',
          displayName: 'Family Member',
        ),
        body:
            'Once /media/:id/url is wired, this detail panel can open originals directly.',
        createdAt: DateTime.utc(2026, 3, 14, 16, 18),
      ),
    ],
    'media-2': <Comment>[
      Comment(
        id: 'comment-3',
        author: const CommentAuthor(
          id: 'user-admin',
          displayName: 'Admin Operator',
        ),
        body:
            'This item is intentionally pending so the upload-progress slice has something to mirror.',
        createdAt: DateTime.utc(2026, 3, 14, 16, 20),
      ),
    ],
  };

  final Map<String, List<Comment>> _commentsByMediaId =
      <String, List<Comment>>{};

  bool _isLoading = false;
  String? _errorMessage;
  String? _activeMediaId;

  bool get isLoading => _isLoading;

  String? get errorMessage => _errorMessage;

  String? get activeMediaId => _activeMediaId;

  List<Comment> commentsFor(String mediaId) {
    if (_config.useDemoData) {
      return _seedCommentsByMediaId[mediaId] ?? const <Comment>[];
    }

    return _commentsByMediaId[mediaId] ?? const <Comment>[];
  }

  Future<void> loadForMedia(String mediaId) async {
    _activeMediaId = mediaId;
    _errorMessage = null;

    if (_config.useDemoData) {
      notifyListeners();
      return;
    }

    _isLoading = true;
    notifyListeners();

    try {
      final response = await _authProvider.withAuthorization(
        (headers) => _transport.get(
          _apiClient.mediaCommentsUri(mediaId),
          headers: headers,
        ),
      );
      final payload = response.asMap();
      final comments =
          payload['comments'] as List<dynamic>? ?? const <dynamic>[];
      _commentsByMediaId[mediaId] = comments
          .whereType<Map<String, dynamic>>()
          .map(Comment.fromJson)
          .toList(growable: false);
    } on ApiException catch (error) {
      _errorMessage = error.message;
    } catch (_) {
      _errorMessage = 'Unable to load comments right now.';
    } finally {
      if (_activeMediaId == mediaId) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  void clear() {
    _commentsByMediaId.clear();
    _isLoading = false;
    _errorMessage = null;
    _activeMediaId = null;
    notifyListeners();
  }
}
