import 'package:background_downloader/background_downloader.dart';

import '../../../../core/network/api_exception.dart';
import 'part_transfer.dart';
import 'upload_checkpoint.dart';

/// Only short-lived object URLs reach native transfers, never API auth tokens.
class NativePartTransfer implements PartTransfer {
  final FileDownloader _downloader = FileDownloader();
  @override
  bool get background => true;
  @override
  Future<String> upload(UploadCheckpoint checkpoint, int partNumber, Uri url,
      int start, int end) async {
    final result = await _downloader.upload(UploadTask(
      taskId: '${checkpoint.id}-$partNumber',
      url: url.toString(),
      filename: 'source',
      directory: 'mynube-uploads/${checkpoint.ownerId}/${checkpoint.id}',
      baseDirectory: BaseDirectory.applicationSupport,
      group: 'mynube-upload-${checkpoint.ownerId}',
      post: 'binary',
      httpRequestMethod: 'PUT',
      headers: {
        'Range': 'bytes=$start-${end - 1}',
        'Content-Type': 'application/octet-stream',
        'Content-Disposition': ''
      },
      requiresWiFi: checkpoint.wifiOnly,
      retries: 0,
      updates: Updates.status,
      displayName: 'Mynube upload',
    ));
    if (result.status != TaskStatus.complete) {
      throw ApiException(
          code: 'OBJECT_TRANSFER',
          statusCode: result.responseStatusCode ?? 0,
          message:
              'Upload paused. Open Mynube and resume when your connection is ready.');
    }
    final etag = result.responseHeaders?['etag'];
    if (etag == null || etag.isEmpty) {
      throw StateError('Storage did not confirm this upload part.');
    }
    return etag;
  }

  @override
  Future<void> cancelOwner(String ownerId) async {
    await _downloader.reset(group: 'mynube-upload-$ownerId');
  }

  @override
  Future<void> cancel(UploadCheckpoint checkpoint) async {
    final tasks = await _downloader.allTasks(
        group: 'mynube-upload-${checkpoint.ownerId}');
    final ids = tasks
        .where((task) => task.taskId.startsWith('${checkpoint.id}-'))
        .map((task) => task.taskId)
        .toList();
    if (ids.isNotEmpty) await _downloader.cancelTasksWithIds(ids);
  }

  @override
  Future<void> prepareOwner(String ownerId) async {
    // Reconcile only this app's upload namespace. Stale native tasks never get
    // rescheduled under a newly authenticated account.
    final tasks = await _downloader.allTasks(allGroups: true);
    final ids = tasks
        .where((task) => task.group.startsWith('mynube-upload-'))
        .map((task) => task.taskId)
        .toList();
    if (ids.isNotEmpty) await _downloader.cancelTasksWithIds(ids);
  }
}
