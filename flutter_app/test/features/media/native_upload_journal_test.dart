import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:familycloud/features/media/data/transfers/native_upload_journal.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../shared/memory_selected_upload_file.dart';

void main() {
  late Directory root;
  NativeUploadJournal journal() =>
      NativeUploadJournal(directory: () async => root, protect: (_) async {});
  setUp(() async {
    root = await Directory.systemTemp.createTemp('mynube-journal-test-');
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });
  MemorySelectedUploadFile file() => MemorySelectedUploadFile(
      name: 'synthetic.png',
      mimeType: 'image/png',
      bytes: Uint8List.fromList([1, 2, 3, 4, 5]));
  test('staged bytes and multipart checkpoint survive a new journal instance',
      () async {
    final first = journal();
    final cp = await first.stage(ownerId: 'first', file: file());
    cp.mediaId = cp.id;
    cp.uploadId = 'synthetic-upload';
    cp.partSize = 3;
    cp.parts[1] = 'etag-1';
    cp.manuallyPaused = true;
    await first.save(cp);
    final loaded = await journal().load('first');
    expect(loaded, hasLength(1));
    expect(loaded.single.parts, {1: 'etag-1'});
    expect(loaded.single.manuallyPaused, isTrue);
    expect(await loaded.single.file.readChunk(1, 4), [2, 3, 4]);
    expect(await journal().load('another-account'), isEmpty);
  });
  test('ready backup history survives clearing only pending source files',
      () async {
    final j = journal();
    final completed = await j.stage(
        ownerId: 'first', file: file(), sourceKey: 'photo-version-1');
    completed.mediaId = 'synthetic-media';
    await j.complete(completed);
    await j.stage(ownerId: 'first', file: file(), sourceKey: 'photo-version-2');
    await j.clearOwner('first');
    expect(await j.load('first'), isEmpty);
    expect(await journal().completedSources('first'), {'photo-version-1'});
  });
  test('clearing one owner cannot remove another owner queue', () async {
    final j = journal();
    await j.stage(ownerId: 'first', file: file());
    await j.stage(ownerId: 'second', file: file());
    await j.clearOwner('first');
    expect(await j.load('first'), isEmpty);
    expect(await j.load('second'), hasLength(1));
  });
  test('path traversal identity cannot escape private staging', () async {
    await expectLater(journal().stage(ownerId: '../outside', file: file()),
        throwsA(isA<FormatException>()));
    expect(await File('${root.path}/outside/source').exists(), isFalse);
  });
  test('staging budget rejects new work before copying source bytes', () async {
    final source = File('${root.path}/mynube-uploads/first/existing/source');
    await source.parent.create(recursive: true);
    final handle = await source.open(mode: FileMode.write);
    await handle.truncate(NativeUploadJournal.maxStagedBytes);
    await handle.close();
    await expectLater(journal().stage(ownerId: 'first', file: file()),
        throwsA(isA<StateError>()));
    expect(await source.length(), NativeUploadJournal.maxStagedBytes);
  });
  test('corrupt checkpoint is preserved for diagnosis instead of deleted',
      () async {
    final cp = await journal().stage(ownerId: 'first', file: file());
    final metadata =
        File('${root.path}/mynube-uploads/first/${cp.id}/checkpoint.json');
    await metadata.writeAsString('{invalid');
    await expectLater(journal().load('first'), throwsA(isA<FormatException>()));
    expect(await File('${metadata.parent.path}/source').exists(), isTrue);
  });
  test('out-of-range confirmed parts fail recovery without deleting the source',
      () async {
    final cp = await journal().stage(ownerId: 'first', file: file());
    cp.mediaId = cp.id;
    cp.uploadId = 'synthetic-upload';
    cp.partSize = 3;
    await journal().save(cp);
    final metadata =
        File('${root.path}/mynube-uploads/first/${cp.id}/checkpoint.json');
    final data =
        jsonDecode(await metadata.readAsString()) as Map<String, dynamic>;
    data['parts'] = {'3': 'invalid-part'};
    await metadata.writeAsString(jsonEncode(data));
    await expectLater(journal().load('first'), throwsA(isA<FormatException>()));
    expect(await File('${metadata.parent.path}/source').exists(), isTrue);
  });
  test('interrupted staging removes only the uncommitted private copy',
      () async {
    final cp = await journal().stage(ownerId: 'first', file: file());
    final folder = Directory('${root.path}/mynube-uploads/first/${cp.id}');
    await File('${folder.path}/checkpoint.json').delete();
    expect(await journal().load('first'), isEmpty);
    expect(await folder.exists(), isFalse);
  });
}
