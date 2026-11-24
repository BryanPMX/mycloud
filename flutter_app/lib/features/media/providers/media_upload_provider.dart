import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../../core/config/app_config.dart';
import '../../../core/connectivity/connectivity_service.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/api_transport.dart';
import '../../../core/network/http_client_factory.dart';
import '../../../core/websocket/upload_progress_event.dart';
import '../../auth/providers/auth_provider.dart';
import '../data/selected_upload_file.dart';
import '../data/upload_picker.dart';
import '../domain/upload_task.dart';
import '../data/transfers/upload_checkpoint.dart';
import '../data/transfers/upload_journal.dart';
import '../data/transfers/part_transfer.dart';
import 'media_list_provider.dart';

class MediaUploadProvider extends ChangeNotifier {
  MediaUploadProvider({
    required AppConfig config,
    required ApiClient apiClient,
    required ApiTransport transport,
    required AuthProvider authProvider,
    required MediaListProvider mediaProvider,
    required ConnectivityService connectivityService,
    UploadFilesPicker? uploadFilesPicker,
    LostUploadFilesRetriever? lostUploadFilesRetriever,
    UploadJournal? uploadJournal,
    PartTransfer? partTransfer,
  }) : _config = config,
       _apiClient = apiClient,
       _transport = transport,
       _authProvider = authProvider,
       _mediaProvider = mediaProvider,
       _connectivityService = connectivityService,
       _uploadFilesPicker = uploadFilesPicker ?? pickUploadFiles,
       _lostUploadFilesRetriever =
           lostUploadFilesRetriever ?? recoverLostUploadFiles,
       _journal = uploadJournal ?? MemoryUploadJournal(),
       _objectTransport = ApiTransport(
         client: createHttpClient(withCredentials: false),
         onReachable: connectivityService.markReachable,
         onUnreachable: connectivityService.markUnreachable,
       ) {
    _partTransfer = partTransfer ?? ForegroundPartTransfer(_objectTransport);
  }

  final AppConfig _config;
  final ApiClient _apiClient;
  final ApiTransport _transport;
  final AuthProvider _authProvider;
  final MediaListProvider _mediaProvider;
  final ConnectivityService _connectivityService;
  final UploadFilesPicker _uploadFilesPicker;
  final LostUploadFilesRetriever _lostUploadFilesRetriever;
  final ApiTransport _objectTransport;
  final UploadJournal _journal;
  late final PartTransfer _partTransfer;
  final Map<String, UploadCheckpoint> _checkpoints = {};
  final Set<String> _scheduled = {};
  final Set<String> _pauseRequested = {};
  final Set<String> _completedSources = {};
  final Set<String> _stagingSources = {};
  final Map<String, UploadProgressEvent> _pendingProgress = {};
  String? _restoredOwner;
  Future<void>? _restoreFuture;
  bool _recoveryReady = false;
  bool get recoveryReady => !resumable || _recoveryReady;
  bool get resumable => _config.enableResumableUploads;
  bool get backgroundTransfers => resumable && _partTransfer.background;
  bool get persistentUploads => resumable && _journal.persistent;

  final List<MediaUploadTask> _tasks = <MediaUploadTask>[];
  final Map<String, String> _taskIdByMediaId = <String, String>{};
  final Set<String> _cancelRequestedTaskIds = <String>{};

  bool _isPickingFiles = false;
  bool _hasRecoveredLostFiles = false;
  String? _errorMessage;
  int _generation = 0;
  bool _disposed = false;
  Future<void> _uploadTail = Future<void>.value();

  List<MediaUploadTask> get tasks => List<MediaUploadTask>.unmodifiable(_tasks);

  bool get isPickingFiles => _isPickingFiles;

  String? get errorMessage => _errorMessage;

  bool get supportsFilePicking => supportsUploadPicking;

  bool get canPickFiles =>
      !_config.useDemoData &&
      supportsUploadPicking &&
      _authProvider.isAuthenticated &&
      !_connectivityService.isOffline;

  String get pickerHint {
    if (_config.useDemoData) {
      return 'This is a sample vault. Add your own memories in the live app.';
    }
    if (!_authProvider.isAuthenticated) {
      return 'Sign in with the live backend to start uploads.';
    }
    if (_connectivityService.isOffline) {
      return _connectivityService.statusMessage;
    }
    if (!supportsUploadPicking) {
      return 'File picking is not available on this platform.';
    }
    return 'Choose photos or videos from your device to send them directly to storage.';
  }

  Future<void> pickAndUpload() async {
    _errorMessage = null;

    if (!_canStartUpload()) {
      return;
    }

    final generation = _generation;
    final ownerId = _authProvider.currentUser?.id;
    _isPickingFiles = true;
    notifyListeners();

    try {
      final files = await _uploadFilesPicker();
      if (generation != _generation ||
          ownerId != _authProvider.currentUser?.id ||
          _disposed) {
        return;
      }
      await queueUploads(files);
    } on UnsupportedError catch (error) {
      if (generation != _generation ||
          ownerId != _authProvider.currentUser?.id ||
          _disposed) {
        return;
      }
      _errorMessage = error.message;
      notifyListeners();
    } catch (_) {
      if (generation != _generation ||
          ownerId != _authProvider.currentUser?.id ||
          _disposed) {
        return;
      }
      _errorMessage = 'Unable to open the upload picker right now.';
      notifyListeners();
    } finally {
      if (generation == _generation &&
          ownerId == _authProvider.currentUser?.id &&
          !_disposed) {
        _isPickingFiles = false;
        notifyListeners();
      }
    }
  }

  Future<int> queueUploads(
    List<SelectedUploadFile> files, {
    String? sourceKey,
    bool wifiOnly = false,
    bool Function()? stillAllowed,
  }) async {
    final generation = _generation;
    final ownerId = _authProvider.currentUser?.id;
    var accepted = 0;
    if (ownerId == null) return accepted;
    for (final file in files) {
      if (stillAllowed != null && !stillAllowed()) return accepted;
      final sizeBytes = await file.loadSizeBytes();
      if (generation != _generation ||
          ownerId != _authProvider.currentUser?.id ||
          _disposed) {
        return accepted;
      }
      if (sizeBytes <= 0 || sizeBytes > 512 * 1024 * 1024) {
        _errorMessage = 'Choose a photo or video no larger than 512 MB.';
        notifyListeners();
        continue;
      }
      if (sourceKey != null &&
          (hasSource(sourceKey) || !_stagingSources.add(sourceKey))) {
        continue;
      }
      UploadCheckpoint checkpoint;
      try {
        checkpoint = await _journal.stage(
          ownerId: ownerId,
          file: file,
          sourceKey: sourceKey,
          wifiOnly: wifiOnly,
        );
      } on StateError catch (error) {
        if (generation == _generation && !_disposed) {
          _errorMessage = error.message;
          notifyListeners();
        }
        return accepted;
      } catch (_) {
        if (generation == _generation && !_disposed) {
          _errorMessage =
              'Couldn’t save this upload on your device. Check free space and try again.';
          notifyListeners();
        }
        return accepted;
      } finally {
        if (sourceKey != null) _stagingSources.remove(sourceKey);
      }
      if (generation != _generation ||
          ownerId != _authProvider.currentUser?.id ||
          _disposed ||
          (stillAllowed != null && !stillAllowed())) {
        await _journal.remove(checkpoint);
        return accepted;
      }
      _checkpoints[checkpoint.id] = checkpoint;
      _tasks.insert(
        0,
        MediaUploadTask(
          localId: checkpoint.id,
          filename: file.name,
          mimeType: file.mimeType,
          sizeBytes: sizeBytes,
          createdAt: checkpoint.createdAt,
          stage: MediaUploadStage.queued,
          progress: 0,
        ),
      );
      accepted++;
      notifyListeners();
      _schedule(checkpoint, generation);
    }
    return accepted;
  }

  bool hasSource(String key) =>
      _completedSources.contains(key) ||
      _checkpoints.values.any((item) => item.sourceKey == key);

  void _schedule(UploadCheckpoint checkpoint, int generation) {
    if (!_scheduled.add(checkpoint.id)) return;
    final ownerId = checkpoint.ownerId;
    _uploadTail = _uploadTail
        .then((_) async {
          if (generation != _generation ||
              ownerId != _authProvider.currentUser?.id ||
              _disposed) {
            return;
          }
          await _uploadFile(
            checkpoint.id,
            checkpoint.file,
            sizeBytes: checkpoint.file.sizeBytes,
            generation: generation,
            ownerId: ownerId,
          );
        })
        .catchError((_) {})
        .whenComplete(() => _scheduled.remove(checkpoint.id));
  }

  Future<void> resumeUpload(String localId, {bool automatic = false}) async {
    final generation = _generation;
    final checkpoint = _checkpoints[localId];
    final task = _taskFor(localId);
    if (!resumable ||
        checkpoint == null ||
        task?.stage != MediaUploadStage.paused ||
        checkpoint.ownerId != _authProvider.currentUser?.id) {
      return;
    }
    _pauseRequested.remove(localId);
    checkpoint.manuallyPaused = false;
    if (!automatic) checkpoint.failures = 0;
    try {
      await _journal.save(checkpoint);
    } catch (_) {
      if (generation == _generation && !_disposed) {
        _errorMessage =
            'Couldn’t save upload progress on your device. Check free space and try again.';
        notifyListeners();
      }
      return;
    }
    if (generation != _generation || _disposed) return;
    _replaceTask(
      localId,
      task!.copyWith(
        stage: MediaUploadStage.queued,
        message: 'Waiting to resume…',
      ),
    );
    if (_scheduled.contains(localId)) {
      final tail = _uploadTail;
      unawaited(
        tail.then((_) {
          if (generation == _generation &&
              _taskFor(localId)?.stage == MediaUploadStage.queued) {
            _schedule(checkpoint, generation);
          }
        }),
      );
    } else {
      _schedule(checkpoint, generation);
    }
  }

  void pauseUpload(String localId, {bool automatic = false}) {
    if (resumable && _checkpoints.containsKey(localId)) {
      _pauseRequested.add(localId);
      if (!automatic) _checkpoints[localId]!.manuallyPaused = true;
      unawaited(_journal.save(_checkpoints[localId]!).catchError((_) {}));
      unawaited(
        _partTransfer.cancel(_checkpoints[localId]!).catchError((_) {}),
      );
    }
  }

  void pauseAutomaticBackups() {
    for (final checkpoint in _checkpoints.values) {
      if (checkpoint.sourceKey != null &&
          !(_taskFor(checkpoint.id)?.isTerminal ?? true)) {
        pauseUpload(checkpoint.id, automatic: true);
      }
    }
  }

  Future<void> updateAutomaticBackupPolicy(bool wifiOnly) async {
    final generation = _generation;
    for (final checkpoint in _checkpoints.values.toList()) {
      if (generation != _generation) return;
      if (checkpoint.sourceKey == null ||
          (_taskFor(checkpoint.id)?.isTerminal ?? true) ||
          checkpoint.wifiOnly == wifiOnly) {
        continue;
      }
      checkpoint.wifiOnly = wifiOnly;
      pauseUpload(checkpoint.id, automatic: true);
      await _journal.save(checkpoint);
    }
  }

  Future<void> resumeAutomaticBackups() async {
    for (final checkpoint in _checkpoints.values.toList()) {
      if (checkpoint.sourceKey != null &&
          !checkpoint.manuallyPaused &&
          checkpoint.failures < 3 &&
          checkpoint.ownerId == _authProvider.currentUser?.id &&
          _taskFor(checkpoint.id)?.stage == MediaUploadStage.paused) {
        await resumeUpload(checkpoint.id, automatic: true);
      }
    }
  }

  Future<void> restorePendingUploads() {
    final ownerId = _authProvider.currentUser?.id;
    if (!resumable || ownerId == null) return Future.value();
    if (_restoredOwner == ownerId && _restoreFuture != null) {
      return _restoreFuture!;
    }
    _restoredOwner = ownerId;
    return _restoreFuture = _restorePending(ownerId, _generation);
  }

  Future<void> reconcileProcessing() async {
    if (!resumable || _disposed) return;
    final generation = _generation;
    for (final checkpoint in _checkpoints.values.toList()) {
      if (generation != _generation) return;
      if (checkpoint.finalized &&
          _taskFor(checkpoint.id)?.stage == MediaUploadStage.processing) {
        _schedule(checkpoint, generation);
      }
    }
  }

  Future<void> _restorePending(String ownerId, int generation) async {
    try {
      await _partTransfer.prepareOwner(ownerId);
      final checkpoints = await _journal.load(ownerId);
      final completed = await _journal.completedSources(ownerId);
      if (generation != _generation ||
          ownerId != _authProvider.currentUser?.id ||
          _disposed) {
        return;
      }
      _completedSources.addAll(completed);
      for (final checkpoint in checkpoints) {
        if (_checkpoints.containsKey(checkpoint.id)) continue;
        _checkpoints[checkpoint.id] = checkpoint;
        if (checkpoint.mediaId != null) {
          _taskIdByMediaId[checkpoint.mediaId!] = checkpoint.id;
        }
        _tasks.add(
          MediaUploadTask(
            localId: checkpoint.id,
            filename: checkpoint.file.name,
            mimeType: checkpoint.file.mimeType,
            sizeBytes: checkpoint.file.sizeBytes,
            createdAt: checkpoint.createdAt,
            mediaId: checkpoint.mediaId,
            stage: MediaUploadStage.paused,
            progress: 0,
            message: 'Recovered safely. Resume this upload when you’re ready.',
          ),
        );
      }
      _recoveryReady = true;
      notifyListeners();
    } catch (_) {
      if (generation != _generation || _disposed) return;
      _errorMessage =
          'Your saved upload queue needs attention. Your files have not been deleted.';
      notifyListeners();
    }
  }

  Future<void> recoverLostFiles() async {
    if (_hasRecoveredLostFiles ||
        _config.useDemoData ||
        !_authProvider.isAuthenticated) {
      return;
    }
    _hasRecoveredLostFiles = true;
    final generation = _generation;
    final ownerId = _authProvider.currentUser?.id;
    bool current() =>
        generation == _generation &&
        ownerId == _authProvider.currentUser?.id &&
        !_disposed;

    try {
      final files = await _lostUploadFilesRetriever();
      if (!current() || files.isEmpty) {
        return;
      }

      // Lost picker data has no trustworthy account ID. Do not assign it to
      // whichever account signs in after the process was killed.
      _errorMessage =
          'Your last selection was interrupted. Choose those photos or videos again to upload them.';
      notifyListeners();
    } on UnsupportedError {
      // Ignore unsupported lost-data recovery on non-Android targets.
    } catch (_) {
      if (!current()) return;
      _errorMessage =
          'Unable to restore the interrupted upload picker session.';
      notifyListeners();
    }
  }

  Future<void> cancelUpload(String localId) async {
    final generation = _generation;
    final task = _taskFor(localId);
    if (task == null || !task.canCancel) {
      return;
    }

    _cancelRequestedTaskIds.add(localId);
    if (task.stage == MediaUploadStage.paused ||
        task.stage == MediaUploadStage.queued) {
      final checkpoint = _checkpoints[localId];
      if (checkpoint?.mediaId != null) await _abortUpload(checkpoint!.mediaId!);
      try {
        if (checkpoint != null) await _journal.remove(checkpoint);
      } catch (_) {
        if (generation == _generation && !_disposed) {
          _errorMessage =
              'The upload stopped. Local file cleanup needs attention; try cancelling again.';
          notifyListeners();
        }
        return;
      }
      if (generation != _generation || _disposed) return;
      _checkpoints.remove(localId);
      _replaceTask(
        localId,
        task.copyWith(
          stage: MediaUploadStage.cancelled,
          message: 'Upload cancelled.',
        ),
      );
      return;
    }
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
    final checkpoint = _checkpoints.remove(localId);
    if (checkpoint != null) {
      unawaited(_journal.remove(checkpoint).catchError((_) {}));
    }
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

    final checkpoint = _checkpoints[localId];
    if (checkpoint != null &&
        (!checkpoint.finalized ||
            task.stage == MediaUploadStage.uploading ||
            task.stage == MediaUploadStage.initializing)) {
      final previous = _pendingProgress[event.mediaId];
      if (previous == null ||
          previous.type == UploadProgressEventType.processingStarted ||
          event.type != UploadProgressEventType.processingStarted) {
        _pendingProgress[event.mediaId] = event;
      }
      return;
    }
    if (task.isTerminal &&
        event.type == UploadProgressEventType.processingStarted) {
      return;
    }
    switch (event.type) {
      case UploadProgressEventType.processingStarted:
        _replaceTask(
          localId,
          task.copyWith(
            stage: MediaUploadStage.processing,
            progress: 1,
            message: 'Checking your file and preparing previews.',
          ),
        );
      case UploadProgressEventType.processingComplete:
        final checkpoint = _checkpoints[localId];
        if (checkpoint != null) unawaited(_finishCheckpoint(checkpoint));
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
    final owners = _checkpoints.values.map((item) => item.ownerId).toSet();
    if (_restoredOwner != null) owners.add(_restoredOwner!);
    _generation++;
    for (final owner in owners) {
      unawaited(
        _partTransfer
            .cancelOwner(owner)
            .then((_) => _journal.clearOwner(owner))
            .catchError((_) {}),
      );
    }
    _checkpoints.clear();
    _completedSources.clear();
    _pendingProgress.clear();
    _stagingSources.clear();
    _scheduled.clear();
    _pauseRequested.clear();
    _restoredOwner = null;
    _restoreFuture = null;
    _recoveryReady = false;
    _uploadTail = Future<void>.value();
    _tasks.clear();
    _taskIdByMediaId.clear();
    _cancelRequestedTaskIds.clear();
    _isPickingFiles = false;
    _hasRecoveredLostFiles = false;
    _errorMessage = null;
    notifyListeners();
  }

  Future<void> _uploadFile(
    String localId,
    SelectedUploadFile file, {
    required int sizeBytes,
    required int generation,
    required String ownerId,
  }) async {
    final checkpoint = _checkpoints[localId];
    if (checkpoint == null) return;
    String? mediaId = checkpoint.mediaId;
    var shouldAbortRemoteUpload = false;

    bool current() =>
        generation == _generation &&
        ownerId == _authProvider.currentUser?.id &&
        !_disposed &&
        _taskFor(localId) != null;
    void check() {
      if (!current()) throw const _UploadCancelled();
      _throwIfCancellationRequested(localId);
      if (_pauseRequested.contains(localId)) throw const _UploadPaused();
    }

    try {
      check();
      _replaceTask(
        localId,
        _taskFor(localId)!.copyWith(
          stage: MediaUploadStage.initializing,
          message: 'Preparing your upload…',
        ),
      );

      if (checkpoint.finalized) {
        final payload = await _authProvider.withAuthorization(
          (headers) => _transport.get(
            _apiClient.endpoint('/media/${checkpoint.mediaId}'),
            headers: headers,
          ),
        );
        check();
        final status = payload.asMap()['status'];
        if (status == 'ready') {
          await _finishCheckpoint(checkpoint);
          if (!current()) return;
          _replaceTask(
            localId,
            _taskFor(localId)!.copyWith(
              stage: MediaUploadStage.complete,
              progress: 1,
              message: 'Your memory is ready.',
            ),
          );
          await _mediaProvider.load();
          return;
        }
        if (status == 'failed') {
          _replaceTask(
            localId,
            _taskFor(localId)!.copyWith(
              stage: MediaUploadStage.failed,
              message:
                  'This file could not be processed. Choose it again to retry.',
            ),
          );
          return;
        }
        _replaceTask(
          localId,
          _taskFor(localId)!.copyWith(
            stage: MediaUploadStage.processing,
            message: 'Uploaded. Checking processing status…',
          ),
        );
        return;
      }
      if (checkpoint.uploadId == null) {
        final initPayload = await _authProvider.withAuthorization(
          (headers) => _transport.postJson(
            _apiClient.uploadInitUri(),
            headers: headers,
            body: <String, Object>{
              'filename': file.name,
              'mime_type': file.mimeType,
              'size_bytes': sizeBytes,
              if (resumable) 'client_upload_id': checkpoint.id,
            },
          ),
        );
        check();
        final initSession = _UploadInitSession.fromJson(initPayload.asMap());
        if (resumable && initSession.mediaId != checkpoint.id) {
          await _abortUpload(initSession.mediaId);
          throw StateError(
            'Resumable uploads need the matching server update. This upload has not started.',
          );
        }
        checkpoint.mediaId = initSession.mediaId;
        checkpoint.uploadId = initSession.uploadId;
        checkpoint.partSize = initSession.partSizeBytes;
        await _journal.save(checkpoint);
        check();
      }
      final initSession = _UploadInitSession(
        mediaId: checkpoint.mediaId!,
        uploadId: checkpoint.uploadId!,
        partSizeBytes: checkpoint.partSize,
      );
      final uploadMediaId = initSession.mediaId;
      final activeUploadId = initSession.uploadId;

      mediaId = uploadMediaId;
      shouldAbortRemoteUpload = true;
      _taskIdByMediaId[uploadMediaId] = localId;

      final totalParts = (sizeBytes / initSession.partSizeBytes).ceil();
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

      final parts = checkpoint.parts.entries
          .map(
            (entry) =>
                _CompletedUploadPart(partNumber: entry.key, etag: entry.value),
          )
          .toList();
      for (var partNumber = 1; partNumber <= totalParts; partNumber++) {
        check();
        if (checkpoint.parts.containsKey(partNumber)) continue;

        final start = (partNumber - 1) * initSession.partSizeBytes;
        final end = math.min(sizeBytes, start + initSession.partSizeBytes);
        check();
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
        check();
        final partUrl = _requiredString(
          presignPayload.asMap(),
          key: 'url',
          errorMessage: 'The upload part URL is missing from the API response.',
        );

        final etag = await _partTransfer.upload(
          checkpoint,
          partNumber,
          Uri.parse(partUrl),
          start,
          end,
        );
        check();
        checkpoint.parts[partNumber] = etag;
        await _journal.save(checkpoint);
        check();

        parts.add(_CompletedUploadPart(partNumber: partNumber, etag: etag));

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

      check();
      parts.sort((a, b) => a.partNumber.compareTo(b.partNumber));

      final completePayload = await _authProvider.withAuthorization(
        (headers) => _transport.postJson(
          _apiClient.uploadCompleteUri(uploadMediaId),
          headers: headers,
          body: <String, Object>{
            'upload_id': activeUploadId,
            'parts': parts
                .map(
                  (part) => <String, Object>{
                    'part_number': part.partNumber,
                    'etag': part.etag,
                  },
                )
                .toList(growable: false),
          },
        ),
      );
      check();
      final completedUpload = _UploadCompleteResult.fromJson(
        completePayload.asMap(),
      );

      shouldAbortRemoteUpload = false;
      checkpoint.finalized = true;
      await _journal.save(checkpoint);
      check();
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
          message: 'Upload complete. Preparing your previews…',
        ),
      );
      final pending = _pendingProgress.remove(completedUpload.mediaId);
      if (pending != null) applyProgressEvent(pending);
    } on _UploadPaused {
      if (!current()) return;
      _replaceTask(
        localId,
        _taskFor(localId)!.copyWith(
          stage: MediaUploadStage.paused,
          message: 'Paused. Your confirmed progress is saved.',
        ),
      );
    } on _UploadCancelled {
      if (!current()) return;
      try {
        await _journal.remove(checkpoint);
      } catch (_) {}
      _checkpoints.remove(localId);
      if (shouldAbortRemoteUpload && mediaId != null) {
        await _abortUpload(mediaId);
      }
      if (!current()) return;

      _replaceTask(
        localId,
        _taskFor(localId)!.copyWith(
          stage: MediaUploadStage.cancelled,
          message: 'Upload cancelled.',
        ),
      );
    } on ApiException catch (error) {
      if (!current()) return;
      if (resumable &&
          (error.statusCode == 0 ||
              error.statusCode == 408 ||
              error.statusCode == 429 ||
              error.statusCode >= 500 ||
              (error.statusCode == 403 && error.code == 'OBJECT_TRANSFER'))) {
        checkpoint.failures++;
        var saved = true;
        try {
          await _journal.save(checkpoint);
        } catch (_) {
          saved = false;
        }
        _replaceTask(
          localId,
          _taskFor(localId)!.copyWith(
            stage: MediaUploadStage.paused,
            message: saved
                ? 'Upload paused. Check your connection and resume when you’re ready.'
                : 'Upload paused. Your device couldn’t save the latest progress. Keep Mynube open and try again.',
          ),
        );
        return;
      }
      if (shouldAbortRemoteUpload && mediaId != null) {
        await _abortUpload(mediaId);
      }
      if (!current()) return;

      _errorMessage = error.message;
      _replaceTask(
        localId,
        _taskFor(
          localId,
        )!.copyWith(stage: MediaUploadStage.failed, message: error.message),
      );
    } on FormatException catch (error) {
      if (!current()) return;
      if (shouldAbortRemoteUpload && mediaId != null) {
        await _abortUpload(mediaId);
      }
      if (!current()) return;

      final message = error.message;
      _errorMessage = message;
      _replaceTask(
        localId,
        _taskFor(
          localId,
        )!.copyWith(stage: MediaUploadStage.failed, message: message),
      );
    } on StateError catch (error) {
      if (!current()) return;
      if (shouldAbortRemoteUpload && mediaId != null) {
        await _abortUpload(mediaId);
      }
      if (!current()) return;

      _errorMessage = error.message;
      _replaceTask(
        localId,
        _taskFor(
          localId,
        )!.copyWith(stage: MediaUploadStage.failed, message: error.message),
      );
    } catch (_) {
      if (!current()) return;
      if (shouldAbortRemoteUpload && mediaId != null) {
        await _abortUpload(mediaId);
      }
      if (!current()) return;

      const message =
          'Unable to finish the upload right now. Please choose the file again to retry.';
      _errorMessage = message;
      _replaceTask(
        localId,
        _taskFor(
          localId,
        )!.copyWith(stage: MediaUploadStage.failed, message: message),
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

  Future<void> _finishCheckpoint(UploadCheckpoint checkpoint) async {
    try {
      await _journal.complete(checkpoint);
      if (checkpoint.ownerId != _authProvider.currentUser?.id || _disposed) {
        return;
      }
      if (checkpoint.sourceKey != null) {
        _completedSources.add(checkpoint.sourceKey!);
      }
      // Keep the in-memory reference until the row is dismissed. Durable staging
      // has been removed only after server processing actually reached ready.
    } catch (_) {
      if (!_disposed) {
        _errorMessage =
            'Your upload is safe in the vault. Local cleanup needs attention.';
        notifyListeners();
      }
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
    if (_disposed) return;
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
  void notifyListeners() {
    if (!_disposed) {
      super.notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _objectTransport.dispose();
    super.dispose();
  }

  bool _canStartUpload() {
    if (_config.useDemoData) {
      _errorMessage = 'Uploads are disabled while demo data is enabled.';
      notifyListeners();
      return false;
    }
    if (!_authProvider.isAuthenticated) {
      _errorMessage = 'Sign in before uploading files.';
      notifyListeners();
      return false;
    }
    if (_connectivityService.isOffline) {
      _errorMessage = _connectivityService.statusMessage;
      notifyListeners();
      return false;
    }
    if (!supportsUploadPicking) {
      _errorMessage = 'File picking is not available on this platform.';
      notifyListeners();
      return false;
    }

    return true;
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
      throw const FormatException(
        'The upload part size is missing or invalid.',
      );
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
  const _CompletedUploadPart({required this.partNumber, required this.etag});

  final int partNumber;
  final String etag;
}

class _UploadCancelled implements Exception {
  const _UploadCancelled();
}

class _UploadPaused implements Exception {
  const _UploadPaused();
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
