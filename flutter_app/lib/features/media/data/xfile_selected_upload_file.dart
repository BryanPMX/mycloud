import 'dart:async';
import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

import 'selected_upload_file.dart';

SelectedUploadFile selectedUploadFileFromXFile(XFile file) {
  return _XFileSelectedUploadFile(file);
}

class _XFileSelectedUploadFile extends SelectedUploadFile {
  _XFileSelectedUploadFile(this._file);

  final XFile _file;

  @override
  String get name => _file.name;

  @override
  String get mimeType => _normalizedMimeType(_file.name, _file.mimeType);

  @override
  int get sizeBytes => _cachedSize ?? 0;

  int? _cachedSize;

  @override
  Future<Uint8List> readChunk(int start, int end) async {
    if (start < 0 || end < start) {
      throw RangeError.range(start, 0, end, 'start');
    }

    final builder = BytesBuilder(copy: false);
    await for (final chunk in _file.openRead(start, end)) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  @override
  Future<int> loadSizeBytes() async {
    return _cachedSize ??= await _file.length();
  }
}

String _normalizedMimeType(String filename, String? rawMimeType) {
  final normalizedMimeType = rawMimeType?.trim().toLowerCase() ?? '';
  if (normalizedMimeType.isNotEmpty) {
    return normalizedMimeType;
  }

  final dotIndex = filename.lastIndexOf('.');
  final extension = dotIndex == -1
      ? ''
      : filename.substring(dotIndex + 1).trim().toLowerCase();

  switch (extension) {
    case 'jpg':
    case 'jpeg':
      return 'image/jpeg';
    case 'png':
      return 'image/png';
    case 'webp':
      return 'image/webp';
    case 'heic':
    case 'heif':
      return 'image/heic';
    case 'gif':
      return 'image/gif';
    case 'mov':
      return 'video/quicktime';
    case 'mp4':
      return 'video/mp4';
    case 'm4v':
      return 'video/x-m4v';
    case 'avi':
      return 'video/x-msvideo';
    default:
      return 'application/octet-stream';
  }
}
