// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

import 'selected_upload_file.dart';

const bool supportsUploadPicking = true;

Future<List<SelectedUploadFile>> pickUploadFiles() async {
  final input = html.FileUploadInputElement()
    ..accept = 'image/*,video/*,.heic,.heif,.mov'
    ..multiple = true
    ..style.display = 'none';

  html.document.body?.children.add(input);

  final completer = Completer<List<SelectedUploadFile>>();
  late final StreamSubscription<html.Event> changeSubscription;
  late final StreamSubscription<html.Event> focusSubscription;

  void finish(List<SelectedUploadFile> files) {
    if (completer.isCompleted) {
      return;
    }

    unawaited(changeSubscription.cancel());
    unawaited(focusSubscription.cancel());
    input.remove();
    completer.complete(files);
  }

  changeSubscription = input.onChange.listen((_) {
    final files = input.files;
    if (files == null || files.isEmpty) {
      finish(const <SelectedUploadFile>[]);
      return;
    }

    finish(
      files
          .map<SelectedUploadFile>((file) => _WebSelectedUploadFile(file))
          .toList(growable: false),
    );
  });

  focusSubscription = html.window.onFocus.listen((_) {
    Future<void>.delayed(const Duration(milliseconds: 300), () {
      final files = input.files;
      if (!completer.isCompleted && (files == null || files.isEmpty)) {
        finish(const <SelectedUploadFile>[]);
      }
    });
  });

  input.click();
  return completer.future;
}

class _WebSelectedUploadFile extends SelectedUploadFile {
  _WebSelectedUploadFile(this._file);

  final html.File _file;

  @override
  String get name => _file.name;

  @override
  String get mimeType => _normalizedMimeType(_file.name, _file.type);

  @override
  int get sizeBytes => _file.size;

  @override
  Future<Uint8List> readChunk(int start, int end) {
    final blob = _file.slice(start, end);
    final reader = html.FileReader();
    final completer = Completer<Uint8List>();

    late final StreamSubscription<html.ProgressEvent> loadSubscription;
    late final StreamSubscription<html.Event> errorSubscription;

    void cleanup() {
      unawaited(loadSubscription.cancel());
      unawaited(errorSubscription.cancel());
    }

    loadSubscription = reader.onLoadEnd.listen((_) {
      cleanup();
      final result = reader.result;
      if (result is ByteBuffer) {
        completer.complete(result.asUint8List());
        return;
      }
      if (result is Uint8List) {
        completer.complete(result);
        return;
      }
      completer.completeError(
        const FormatException('Unable to read the selected file chunk.'),
      );
    });

    errorSubscription = reader.onError.listen((_) {
      cleanup();
      completer.completeError(
        StateError('Unable to read the selected file chunk.'),
      );
    });

    reader.readAsArrayBuffer(blob);
    return completer.future;
  }
}

String _normalizedMimeType(String filename, String rawMimeType) {
  final normalizedMimeType = rawMimeType.trim().toLowerCase();
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
