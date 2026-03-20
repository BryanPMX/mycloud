import 'dart:typed_data';

import 'package:familycloud/features/media/data/selected_upload_file.dart';

class MemorySelectedUploadFile extends SelectedUploadFile {
  MemorySelectedUploadFile({
    required this.name,
    required this.mimeType,
    required Uint8List bytes,
  })  : _bytes = bytes,
        sizeBytes = bytes.lengthInBytes;

  final Uint8List _bytes;

  @override
  final String name;

  @override
  final String mimeType;

  @override
  final int sizeBytes;

  @override
  Future<Uint8List> readChunk(int start, int end) async {
    final normalizedStart = start.clamp(0, _bytes.lengthInBytes);
    final normalizedEnd = end.clamp(normalizedStart, _bytes.lengthInBytes);
    return Uint8List.sublistView(_bytes, normalizedStart, normalizedEnd);
  }
}
