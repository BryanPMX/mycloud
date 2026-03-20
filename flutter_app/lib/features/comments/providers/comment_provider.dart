import 'package:flutter/foundation.dart';

import '../../../core/config/app_config.dart';
import '../../../core/connectivity/connectivity_service.dart';
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
    required ConnectivityService connectivityService,
  })  : _config = config,
        _apiClient = apiClient,
        _transport = transport,
        _authProvider = authProvider,
        _connectivityService = connectivityService {
    if (_config.useDemoData) {
      for (final entry in _seedCommentsByMediaId.entries) {
        _commentsByMediaId[entry.key] = List<Comment>.of(entry.value);
      }
    }
  }

  final AppConfig _config;
  final ApiClient _apiClient;
  final ApiTransport _transport;
  final AuthProvider _authProvider;
  final ConnectivityService _connectivityService;

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
  bool _isSubmitting = false;
  String? _errorMessage;
  String? _activeMediaId;
  final Set<String> _deletingCommentIds = <String>{};

  bool get isLoading => _isLoading;

  bool get isSubmitting => _isSubmitting;

  String? get errorMessage => _errorMessage;

  String? get activeMediaId => _activeMediaId;

  bool isDeletingComment(String commentId) =>
      _deletingCommentIds.contains(commentId);

  List<Comment> commentsFor(String mediaId) {
    return _commentsByMediaId[mediaId] ?? const <Comment>[];
  }

  Future<void> loadForMedia(String mediaId) async {
    _activeMediaId = mediaId;
    _errorMessage = null;

    if (_config.useDemoData) {
      notifyListeners();
      return;
    }
    if (_connectivityService.isOffline) {
      _errorMessage = _connectivityService.statusMessage;
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

  Future<bool> addComment(String mediaId, String body) async {
    final author = _authProvider.currentUser;
    final trimmedBody = body.trim();

    if (author == null) {
      _errorMessage = 'Sign in again before posting a comment.';
      notifyListeners();
      return false;
    }
    if (trimmedBody.isEmpty) {
      _errorMessage = 'Comment text cannot be empty.';
      notifyListeners();
      return false;
    }
    if (!_config.useDemoData && _connectivityService.isOffline) {
      _errorMessage = _connectivityService.statusMessage;
      notifyListeners();
      return false;
    }

    _activeMediaId = mediaId;
    _isSubmitting = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final comment = _config.useDemoData
          ? Comment(
              id: 'demo-comment-${DateTime.now().microsecondsSinceEpoch}',
              author: CommentAuthor(
                id: author.id,
                displayName: author.displayName,
                avatarUrl: author.avatarUrl,
              ),
              body: trimmedBody,
              createdAt: DateTime.now().toUtc(),
            )
          : Comment.fromJson(
              (await _authProvider.withAuthorization(
                (headers) => _transport.postJson(
                  _apiClient.mediaCommentsUri(mediaId),
                  headers: headers,
                  body: <String, String>{'body': trimmedBody},
                ),
              ))
                  .asMap(),
            );

      _commentsByMediaId[mediaId] = List<Comment>.of(
        _commentsByMediaId[mediaId] ?? const <Comment>[],
      )..add(comment);
      notifyListeners();
      return true;
    } on ApiException catch (error) {
      _errorMessage = error.message;
      notifyListeners();
      return false;
    } catch (_) {
      _errorMessage = 'Unable to post a comment right now.';
      notifyListeners();
      return false;
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }

  Future<bool> deleteComment(String mediaId, String commentId) async {
    final comments = _commentsByMediaId[mediaId];
    if (comments == null || comments.isEmpty) {
      return false;
    }
    if (!_config.useDemoData && _connectivityService.isOffline) {
      _errorMessage = _connectivityService.statusMessage;
      notifyListeners();
      return false;
    }

    _activeMediaId = mediaId;
    _errorMessage = null;
    _deletingCommentIds.add(commentId);
    notifyListeners();

    try {
      if (!_config.useDemoData) {
        await _authProvider.withAuthorization(
          (headers) => _transport.delete(
            _apiClient.mediaCommentUri(mediaId, commentId),
            headers: headers,
          ),
        );
      }

      _commentsByMediaId[mediaId] = comments
          .where((comment) => comment.id != commentId)
          .toList(growable: false);
      notifyListeners();
      return true;
    } on ApiException catch (error) {
      _errorMessage = error.message;
      notifyListeners();
      return false;
    } catch (_) {
      _errorMessage = 'Unable to delete that comment right now.';
      notifyListeners();
      return false;
    } finally {
      _deletingCommentIds.remove(commentId);
      notifyListeners();
    }
  }

  void clear() {
    _commentsByMediaId.clear();
    if (_config.useDemoData) {
      for (final entry in _seedCommentsByMediaId.entries) {
        _commentsByMediaId[entry.key] = List<Comment>.of(entry.value);
      }
    }
    _isLoading = false;
    _isSubmitting = false;
    _errorMessage = null;
    _activeMediaId = null;
    _deletingCommentIds.clear();
    notifyListeners();
  }
}
