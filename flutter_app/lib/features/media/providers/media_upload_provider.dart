import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/api_transport.dart';
import '../../../core/network/http_client_factory.dart';
import '../../../core/websocket/upload_progress_event.dart';
import '../../auth/providers/auth_provider.dart';
import '../data/selected_upload_file.dart';
import '../data/upload_picker.dart';
import '../domain/upload_task.dart';
import 'media_list_provider.dart';

class MediaUploadProvider extends ChangeNotifier {
  MediaUploadProvider({
    required AppConfig config,
    required ApiClient apiClient,
    required ApiTransport transport,
    required AuthProvider authProvider,
    required MediaListProvider mediaProvider,
  })  : _config = config,
        _apiClient = apiClient,
        _transport = transport,
        _authProvider = authProvider,
        _mediaProvider = mediaProvider,
        _objectTransport = ApiTransport(
          client: createHttpClient(withCredentials: false),
        );

  final AppConfig _config;
  final ApiClient _apiClient;
  final ApiTransport _transport;
  final AuthProvider _authProvider;
  final MediaListProvider _mediaProvider;
  final ApiTransport _objectTransport;

  final List<MediaUploadTask> _tasks = <MediaUploadTask>[];
  final Map<String, String> _taskIdByMediaId = <String, String>{};
  final Set<String> _cancelRequestedTaskIds = <String>{};

  bool _isPickingFiles = false;
  String? _errorMessage;
  int _taskSequence = 0;

  List<MediaUploadTask> get tasks => List<MediaUploadTask>.unmodifiable(_tasks);

  bool get isPickingFiles => _isPickingFiles;

  String? get errorMessage => _errorMessage;

  bool get supportsFilePicking => supportsUploadPicking;

  bool get canPickFiles =>
      !_config.useDemoData && supportsUploadPicking && _authProvider.isAuthenticated;

  String get pickerHint {
    if (_config.useDemoData) {
      return 'Demo mode keeps multipart uploads disabled.';
    }
    if (!_authProvider.isAuthenticated) {
      return 'Sign in with the live backend to start uploads.';
    }
    if (!supportsUploadPicking) {
      return 'File picking is currently implemented for the Flutter web target.';
    }
    return 'Choose images or videos to send them directly to storage.';
  }

  Future<void> pickAndUpload() async {
    _errorMessage = null;

    if (_config.useDemoData) {
      _errorMessage = 'Uploads are disabled while demo data is enabled.';
      notifyListeners();
      return;
    }

    if (!_authProvider.isAuthenticated) {
      _errorMessage = 'Sign in before uploading files.';
      notifyListeners();
      return;
    }

    if (!supportsUploadPicking) {
      _errorMessage =
          'File picking is currently implemented for the Flutter web target.';
      notifyListeners();
      return;
    }

    _isPickingFiles = true;
    notifyListeners();

    try {
      final files = await pickUploadFiles();
      for (final file in files) {
        final task = MediaUploadTask(
          localId: 'upload-${_taskSequence++}',
          filename: file.name,
          mimeType: file.mimeType,
          sizeBytes: file.sizeBytes,
          createdAt: DateTime.now().toUtc(),
          stage: MediaUploadStage.queued,
          progress: 0,
        );
        _tasks.insert(0, task);
        notifyListeners();
        unawaited(_uploadFile(task.localId, file));
      }
    } on UnsupportedError catch (error) {
      _errorMessage = error.message;
      notifyListeners();
    } catch (_) {
      _errorMessage = 'Unable to open the upload picker right now.';
      notifyListeners();
    } finally {
      _isPickingFiles = false;
      notifyListeners();
    }
  }

  Future<void> cancelUpload(String localId) async {
    final task = _taskFor(localId);
    if (task == null || !task.canCancel) {
      return;
    }

    _cancelRequestedTaskIds.add(localId);
    _replaceTask(
      localId,
      task.copyWith(message: 'Cancelling after the current upload step...'),
    );
  }

  void dismissUpload(String localId) {
    final index = _tasks.indexWhere((task) => task.localId == localId);
    if (index == -1) {
      return;
    }

    final mediaId = _tasks[index].mediaId;
    if (mediaId != null) {
      _taskIdByMediaId.remove(mediaId);
    }

    _cancelRequestedTaskIds.remove(localId);
    _tasks.removeAt(index);
    notifyListeners();
  }

  void applyProgressEvent(UploadProgressEvent event) {
    final localId = _taskIdByMediaId[event.mediaId];
    if (localId == null) {
      return;
    }

    final task = _taskFor(localId);
    if (task == null) {
      return;
    }

    switch (event.type) {
      case UploadProgressEventType.processingStarted:
        _replaceTask(
          localId,
          task.copyWith(
            stage: MediaUploadStage.processing,
            progress: 1,
            message: 'Worker started scanning and generating thumbnails.',
          ),
        );
      case UploadProgressEventType.processingComplete:
        _replaceTask(
          localId,
          task.copyWith(
            stage: MediaUploadStage.complete,
            progress: 1,
            message: 'Processing complete. The item is ready in the library.',
          ),
        );
      case UploadProgressEventType.processingFailed:
        _replaceTask(
          localId,
          task.copyWith(
            stage: MediaUploadStage.failed,
            progress: 1,
            message: event.reason?.isNotEmpty == true
                ? event.reason
                : 'Media processing failed.',
          ),
        );
    }
  }

  void reset() {
    _tasks.clear();
    _taskIdByMediaId.clear();
    _cancelRequestedTaskIds.clear();
    _isPickingFiles = false;
    _errorMessage = null;
    notifyListeners();
  }

  Future<void> _uploadFile(
    String localId,
    SelectedUploadFile file,
  ) async {
    String? mediaId;
    var shouldAbortRemoteUpload = false;

    try {
      _replaceTask(
        localId,
        _taskFor(localId)!.copyWith(
          stage: MediaUploadStage.initializing,
          message: 'Creating multipart upload session...',
        ),
      );

      final initPayload = await _authProvider.withAuthorization(
        (headers) => _transport.postJson(
          _apiClient.uploadInitUri(),
          headers: headers,
          body: <String, Object>{
            'filename': file.name,
            'mime_type': file.mimeType,
            'size_bytes': file.sizeBytes,
          },
        ),
      );
      final initSession = _UploadInitSession.fromJson(initPayload.asMap());
      final uploadMediaId = initSession.mediaId;
      final activeUploadId = initSession.uploadId;

      mediaId = uploadMediaId;
      shouldAbortRemoteUpload = true;
      _taskIdByMediaId[uploadMediaId] = localId;

      final totalParts = (file.sizeBytes / initSession.partSizeBytes).ceil();
      _replaceTask(
        localId,
        _taskFor(localId)!.copyWith(
          stage: MediaUploadStage.uploading,
          progress: 0,
          mediaId: mediaId,
          completedParts: 0,
          totalParts: totalParts,
          message: 'Uploading part 1 of $totalParts...',
        ),
      );

      final parts = <_CompletedUploadPart>[];
      for (var partNumber = 1; partNumber <= totalParts; partNumber++) {
        _throwIfCancellationRequested(localId);

        final start = (partNumber - 1) * initSession.partSizeBytes;
        final end = math.min(file.sizeBytes, start + initSession.partSizeBytes);
        final chunk = await file.readChunk(start, end);

        final presignPayload = await _authProvider.withAuthorization(
          (headers) => _transport.postJson(
            _apiClient.uploadPartUri(uploadMediaId),
            headers: headers,
            body: <String, Object>{
              'upload_id': activeUploadId,
              'part_number': partNumber,
            },
          ),
        );
        final partUrl = _requiredString(
          presignPayload.asMap(),
          key: 'url',
          errorMessage: 'The upload part URL is missing from the API response.',
        );

        final storageResponse = await _objectTransport.putBytes(
          Uri.parse(partUrl),
          body: chunk,
        );
        final etag = _etagFromHeaders(storageResponse.headers);
        if (etag == null) {
          throw StateError(
            'The storage response did not include the required ETag header.',
          );
        }

        parts.add(
          _CompletedUploadPart(partNumber: partNumber, etag: etag),
        );

        _replaceTask(
          localId,
          _taskFor(localId)!.copyWith(
            stage: MediaUploadStage.uploading,
            progress: partNumber / totalParts,
            completedParts: partNumber,
            totalParts: totalParts,
            message: partNumber == totalParts
                ? 'Finalizing upload...'
                : 'Uploading part ${partNumber + 1} of $totalParts...',
          ),
        );
      }

      _throwIfCancellationRequested(localId);

      final completePayload = await _authProvider.withAuthorization(
        (headers) => _transport.postJson(
          _apiClient.uploadCompleteUri(uploadMediaId),
          headers: headers,
          body: <String, Object>{
            'upload_id': activeUploadId,
            'parts': parts
                .map((part) => <String, Object>{
                      'part_number': part.partNumber,
                      'etag': part.etag,
                    })
                .toList(growable: false),
          },
        ),
      );
      final completedUpload = _UploadCompleteResult.fromJson(
        completePayload.asMap(),
      );

      shouldAbortRemoteUpload = false;
      final ownerId = _authProvider.currentUser?.id ?? '';
      _mediaProvider.insertPendingUpload(
        mediaId: completedUpload.mediaId,
        ownerId: ownerId,
        filename: completedUpload.filename,
        mimeType: file.mimeType,
        sizeBytes: completedUpload.sizeBytes,
      );
      _replaceTask(
        localId,
        _taskFor(localId)!.copyWith(
          stage: MediaUploadStage.processing,
          progress: 1,
          mediaId: completedUpload.mediaId,
          message: 'Upload complete. Waiting for virus scan and thumbnails...',
        ),
      );
    } on _UploadCancelled {
      if (shouldAbortRemoteUpload && mediaId != null) {
        await _abortUpload(mediaId);
      }

      _replaceTask(
        localId,
        _taskFor(localId)!.copyWith(
          stage: MediaUploadStage.cancelled,
          message: 'Upload cancelled.',
        ),
      );
    } on ApiException catch (error) {
      if (shouldAbortRemoteUpload && mediaId != null) {
        await _abortUpload(mediaId);
      }

      _errorMessage = error.message;
      _replaceTask(
        localId,
        _taskFor(localId)!.copyWith(
          stage: MediaUploadStage.failed,
          message: error.message,
        ),
      );
    } on FormatException catch (error) {
      if (shouldAbortRemoteUpload && mediaId != null) {
        await _abortUpload(mediaId);
      }

      final message = error.message;
      _errorMessage = message;
      _replaceTask(
        localId,
        _taskFor(localId)!.copyWith(
          stage: MediaUploadStage.failed,
          message: message,
        ),
      );
    } on StateError catch (error) {
      if (shouldAbortRemoteUpload && mediaId != null) {
        await _abortUpload(mediaId);
      }

      _errorMessage = error.message;
      _replaceTask(
        localId,
        _taskFor(localId)!.copyWith(
          stage: MediaUploadStage.failed,
          message: error.message,
        ),
      );
    } catch (_) {
      if (shouldAbortRemoteUpload && mediaId != null) {
        await _abortUpload(mediaId);
      }

      const message = 'Unable to finish the multipart upload right now.';
      _errorMessage = message;
      _replaceTask(
        localId,
        _taskFor(localId)!.copyWith(
          stage: MediaUploadStage.failed,
          message: message,
        ),
      );
    } finally {
      _cancelRequestedTaskIds.remove(localId);
    }
  }

  Future<void> _abortUpload(String mediaId) async {
    try {
      await _authProvider.withAuthorization(
        (headers) => _transport.delete(
          _apiClient.abortUploadUri(mediaId),
          headers: headers,
        ),
      );
    } catch (_) {
      // Keep the local task failure visible even if abort cleanup fails.
    }
  }

  MediaUploadTask? _taskFor(String localId) {
    for (final task in _tasks) {
      if (task.localId == localId) {
        return task;
      }
    }
    return null;
  }

  void _replaceTask(String localId, MediaUploadTask updatedTask) {
    final index = _tasks.indexWhere((task) => task.localId == localId);
    if (index == -1) {
      return;
    }

    _tasks[index] = updatedTask;
    notifyListeners();
  }

  void _throwIfCancellationRequested(String localId) {
    if (_cancelRequestedTaskIds.contains(localId)) {
      throw const _UploadCancelled();
    }
  }

  @override
  void dispose() {
    _objectTransport.dispose();
    super.dispose();
  }
}

class _UploadInitSession {
  const _UploadInitSession({
    required this.mediaId,
    required this.uploadId,
    required this.partSizeBytes,
  });

  final String mediaId;
  final String uploadId;
  final int partSizeBytes;

  factory _UploadInitSession.fromJson(Map<String, dynamic> json) {
    final partSizeBytes = json['part_size_bytes'];
    final normalizedPartSize = partSizeBytes is num ? partSizeBytes.toInt() : 0;
    if (normalizedPartSize <= 0) {
      throw const FormatException('The upload part size is missing or invalid.');
    }

    return _UploadInitSession(
      mediaId: _requiredString(
        json,
        key: 'media_id',
        errorMessage: 'The upload media id is missing from the API response.',
      ),
      uploadId: _requiredString(
        json,
        key: 'upload_id',
        errorMessage: 'The upload session id is missing from the API response.',
      ),
      partSizeBytes: normalizedPartSize,
    );
  }
}

class _UploadCompleteResult {
  const _UploadCompleteResult({
    required this.mediaId,
    required this.filename,
    required this.sizeBytes,
  });

  final String mediaId;
  final String filename;
  final int sizeBytes;

  factory _UploadCompleteResult.fromJson(Map<String, dynamic> json) {
    return _UploadCompleteResult(
      mediaId: _requiredString(
        json,
        key: 'id',
        errorMessage: 'The uploaded media id is missing from the API response.',
      ),
      filename: _requiredString(
        json,
        key: 'filename',
        errorMessage: 'The uploaded filename is missing from the API response.',
      ),
      sizeBytes: (json['size_bytes'] as num?)?.toInt() ?? 0,
    );
  }
}

class _CompletedUploadPart {
  const _CompletedUploadPart({
    required this.partNumber,
    required this.etag,
  });

  final int partNumber;
  final String etag;
}

class _UploadCancelled implements Exception {
  const _UploadCancelled();
}

String _requiredString(
  Map<String, dynamic> json, {
  required String key,
  required String errorMessage,
}) {
  final value = (json[key] as String? ?? '').trim();
  if (value.isEmpty) {
    throw FormatException(errorMessage);
  }
  return value;
}

String? _etagFromHeaders(Map<String, String> headers) {
  for (final entry in headers.entries) {
    if (entry.key.toLowerCase() == 'etag') {
      final value = entry.value.trim();
      return value.isEmpty ? null : value;
    }
  }
  return null;
}
