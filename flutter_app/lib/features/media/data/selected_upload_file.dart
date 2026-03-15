import 'dart:typed_data';

abstract class SelectedUploadFile {
  const SelectedUploadFile();

  String get name;

  String get mimeType;

  int get sizeBytes;

  Future<Uint8List> readChunk(int start, int end);
}
