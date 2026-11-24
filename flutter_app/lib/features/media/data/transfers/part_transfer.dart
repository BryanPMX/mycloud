import '../../../../core/network/api_transport.dart';
import 'upload_checkpoint.dart';

abstract interface class PartTransfer {
  bool get background;
  Future<String> upload(
      UploadCheckpoint checkpoint, int partNumber, Uri url, int start, int end);
  Future<void> cancelOwner(String ownerId);
  Future<void> prepareOwner(String ownerId);
  Future<void> cancel(UploadCheckpoint checkpoint);
}

class ForegroundPartTransfer implements PartTransfer {
  ForegroundPartTransfer(this.transport);
  final ApiTransport transport;
  @override
  bool get background => false;
  @override
  Future<String> upload(UploadCheckpoint checkpoint, int partNumber, Uri url,
      int start, int end) async {
    final bytes = await checkpoint.file.readChunk(start, end);
    if (bytes.length != end - start) {
      throw StateError('The selected file changed. Choose it again.');
    }
    final response = await transport.putBytes(url, body: bytes);
    final etag = response.headers.entries
        .where((e) => e.key.toLowerCase() == 'etag')
        .firstOrNull
        ?.value;
    if (etag == null || etag.isEmpty) {
      throw StateError('Storage did not confirm this upload part.');
    }
    return etag;
  }

  @override
  Future<void> cancelOwner(String ownerId) async {}
  @override
  Future<void> prepareOwner(String ownerId) async {}
  @override
  Future<void> cancel(UploadCheckpoint checkpoint) async {}
}
