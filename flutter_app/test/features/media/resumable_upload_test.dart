import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:familycloud/core/network/api_exception.dart';
import 'package:familycloud/core/websocket/upload_progress_event.dart';
import 'package:familycloud/features/media/domain/upload_task.dart';
import 'package:familycloud/features/media/data/transfers/upload_journal.dart';
import 'package:familycloud/features/media/data/transfers/upload_checkpoint.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import '../../shared/memory_selected_upload_file.dart';
import '../../shared/transfer_harness.dart';

MemorySelectedUploadFile fixture() => MemorySelectedUploadFile(
  name: 'synthetic.png',
  mimeType: 'image/png',
  bytes: Uint8List.fromList([1, 2, 3, 4, 5, 6]),
);
void main() {
  test(
    'a device write failure cannot resume or lose the paused upload',
    () async {
      final journal = FailingJournal();
      final h = TransferHarness(journal: journal);
      addTearDown(h.dispose);
      h.parts.onPart = (_, __) async =>
          throw const ApiException(statusCode: 0, message: 'Synthetic outage');
      await h.uploads.queueUploads([fixture()]);
      await h.waitForStage(MediaUploadStage.paused);
      journal.failWrites = true;
      await h.uploads.resumeUpload(h.uploads.tasks.single.localId);
      expect(h.parts.calls, [1]);
      expect(h.uploads.tasks.single.stage, MediaUploadStage.paused);
      expect(h.uploads.errorMessage, contains('free space'));
      expect(await journal.load('first'), hasLength(1));
    },
  );
  test(
    'resume reuses session and skips already confirmed multipart data',
    () async {
      final h = TransferHarness();
      addTearDown(h.dispose);
      var failed = false;
      h.parts.onPart = (cp, n) async {
        if (n == 2 && !failed) {
          failed = true;
          throw const ApiException(statusCode: 0, message: 'Synthetic outage');
        }
        return 'etag-$n';
      };
      await h.uploads.queueUploads([fixture()]);
      await h.waitForStage(MediaUploadStage.paused);
      expect(h.parts.calls, [1, 2]);
      await h.uploads.resumeUpload(h.uploads.tasks.single.localId);
      await h.waitForStage(MediaUploadStage.processing);
      expect(h.parts.calls, [1, 2, 2]);
      expect(
        h.requests.where((r) => r.url.path.endsWith('/init')),
        hasLength(1),
      );
      final completed =
          jsonDecode(
                h.requests
                    .firstWhere((r) => r.url.path.endsWith('/complete'))
                    .body,
              )
              as Map;
      expect((completed['parts'] as List).map((p) => p['part_number']), [1, 2]);
    },
  );
  test('lost init response retries the same client upload identity', () async {
    var count = 0;
    final ids = <String>[];
    final h = TransferHarness(
      onRequest: (r) async {
        if (r.url.path.endsWith('/init')) {
          ids.add((jsonDecode(r.body) as Map)['client_upload_id'] as String);
          if (++count == 1) {
            throw const ApiException(statusCode: 0, message: 'Lost response');
          }
        }
        return null;
      },
    );
    addTearDown(h.dispose);
    await h.uploads.queueUploads([fixture()]);
    await h.waitForStage(MediaUploadStage.paused);
    await h.uploads.resumeUpload(h.uploads.tasks.single.localId);
    await h.waitForStage(MediaUploadStage.processing);
    expect(ids, hasLength(2));
    expect(ids[0], ids[1]);
  });
  test(
    'completion event before complete HTTP response does not delete staging early',
    () async {
      final response = Completer<http.Response>();
      final h = TransferHarness(
        onRequest: (r) async =>
            r.url.path.endsWith('/complete') ? response.future : null,
      );
      addTearDown(h.dispose);
      await h.uploads.queueUploads([fixture()]);
      final deadline = DateTime.now().add(const Duration(seconds: 3));
      while (!h.requests.any((r) => r.url.path.endsWith('/complete'))) {
        if (DateTime.now().isAfter(deadline)) {
          fail('Completion request timed out');
        }
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      final task = h.uploads.tasks.single;
      h.uploads.applyProgressEvent(
        UploadProgressEvent(
          type: UploadProgressEventType.processingComplete,
          mediaId: task.mediaId!,
        ),
      );
      response.complete(
        http.Response(
          jsonEncode({
            'id': task.mediaId,
            'filename': 'synthetic.png',
            'size_bytes': 6,
          }),
          200,
        ),
      );
      await h.waitForStage(MediaUploadStage.complete);
      expect(h.uploads.tasks.single.stage, MediaUploadStage.complete);
    },
  );
  test('overlapping automatic sources stage only one upload', () async {
    final h = TransferHarness();
    addTearDown(h.dispose);
    final accepted = await Future.wait([
      h.uploads.queueUploads([fixture()], sourceKey: 'same-photo'),
      h.uploads.queueUploads([fixture()], sourceKey: 'same-photo'),
    ]);
    expect(accepted.reduce((a, b) => a + b), 1);
    expect(h.uploads.tasks, hasLength(1));
  });
  test('revoked backup consent cannot enqueue a late staged file', () async {
    final h = TransferHarness();
    addTearDown(h.dispose);
    expect(
      await h.uploads.queueUploads(
        [fixture()],
        sourceKey: 'photo',
        stillAllowed: () => false,
      ),
      0,
    );
    expect(h.requests, isEmpty);
  });
  test('automatic resume honors an explicit manual pause', () async {
    final h = TransferHarness();
    addTearDown(h.dispose);
    h.parts.onPart = (_, __) async =>
        throw const ApiException(statusCode: 0, message: 'Synthetic outage');
    await h.uploads.queueUploads([fixture()], sourceKey: 'automatic-source');
    await h.waitForStage(MediaUploadStage.paused);
    h.uploads.pauseUpload(h.uploads.tasks.single.localId);
    await h.uploads.resumeAutomaticBackups();
    expect(h.parts.calls, [1]);
    expect(h.uploads.tasks.single.stage, MediaUploadStage.paused);
  });
  test('automatic retries stop after three transient failures', () async {
    final h = TransferHarness();
    addTearDown(h.dispose);
    h.parts.onPart = (_, __) async =>
        throw const ApiException(statusCode: 0, message: 'Synthetic outage');
    await h.uploads.queueUploads([fixture()], sourceKey: 'automatic-source');
    await h.waitForStage(MediaUploadStage.paused);
    for (var retry = 0; retry < 2; retry++) {
      await h.uploads.resumeAutomaticBackups();
      await h.waitForStage(MediaUploadStage.paused);
    }
    await h.uploads.resumeAutomaticBackups();
    expect(h.parts.calls, [1, 1, 1]);
    expect(h.uploads.tasks.single.stage, MediaUploadStage.paused);
  });
}

class FailingJournal extends MemoryUploadJournal {
  bool failWrites = false;
  @override
  Future<void> save(UploadCheckpoint checkpoint) async {
    if (failWrites) throw StateError('Synthetic device write failure');
    await super.save(checkpoint);
  }
}
