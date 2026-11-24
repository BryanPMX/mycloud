import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:familycloud/features/media/data/transfers/native_upload_journal.dart';
import 'package:familycloud/features/media/data/transfers/native_part_transfer.dart';
import '../test/shared/memory_selected_upload_file.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const acknowledged = String.fromEnvironment('NATIVE_UPLOAD_TEST_ACK') ==
      'isolated-synthetic-target';
  const endpoint = String.fromEnvironment('NATIVE_UPLOAD_TEST_URL');
  testWidgets(
      'native protected staging and file-range transfer survive journal reconstruction',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: Center(
                child: Text(
                    'Mynube native transfer test • synthetic bytes only')))));
    final uri = Uri.parse(endpoint);
    expect(uri.scheme, 'https');
    const owner = 'native-acceptance';
    final journal = NativeUploadJournal();
    final transfer = NativePartTransfer();
    final cp = await journal.stage(
        ownerId: owner,
        file: MemorySelectedUploadFile(
            name: 'synthetic.png',
            mimeType: 'image/png',
            bytes: Uint8List.fromList([1, 2, 3, 4, 5, 6])));
    try {
      final first = await transfer
          .upload(cp, 1, uri.replace(path: '${uri.path}/1'), 0, 3)
          .timeout(const Duration(seconds: 60));
      expect(first, contains('native-etag-1'));
      cp.mediaId = cp.id;
      cp.uploadId = 'synthetic-native-session';
      cp.partSize = 3;
      cp.parts[1] = first;
      await journal.save(cp);
      final recovered = (await NativeUploadJournal().load(owner)).single;
      expect(recovered.parts[1], first);
      final second = await transfer
          .upload(recovered, 2, uri.replace(path: '${uri.path}/2'), 3, 6)
          .timeout(const Duration(seconds: 60));
      expect(second, contains('native-etag-2'));
      expect(await recovered.file.readChunk(0, 6), [1, 2, 3, 4, 5, 6]);
    } finally {
      await transfer.cancelOwner(owner);
      await journal.clearOwner(owner);
    }
  },
      skip: !acknowledged ||
          endpoint.isEmpty ||
          (!Platform.isIOS && !Platform.isAndroid));
}
