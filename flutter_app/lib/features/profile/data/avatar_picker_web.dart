// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

import '../../media/data/selected_upload_file.dart';

const bool supportsAvatarPicking = true;

Future<SelectedUploadFile?> pickAvatarFile() async {
  final input = html.FileUploadInputElement()
    ..accept = 'image/*,.heic,.heif'
    ..multiple = false
    ..style.display = 'none';

  html.document.body?.children.add(input);

  final completer = Completer<SelectedUploadFile?>();
  late final StreamSubscription<html.Event> changeSubscription;
  late final StreamSubscription<html.Event> focusSubscription;

  void finish(SelectedUploadFile? file) {
    if (completer.isCompleted) {
      return;
    }

    unawaited(changeSubscription.cancel());
    unawaited(focusSubscription.cancel());
    input.remove();
    completer.complete(file);
  }

  changeSubscription = input.onChange.listen((_) {
    final files = input.files;
    if (files == null || files.isEmpty) {
      finish(null);
      return;
    }

    finish(_WebSelectedAvatarFile(files.first));
  });

  focusSubscription = html.window.onFocus.listen((_) {
    Future<void>.delayed(const Duration(milliseconds: 300), () {
      final files = input.files;
      if (!completer.isCompleted && (files == null || files.isEmpty)) {
        finish(null);
      }
    });
  });

  input.click();
  return completer.future;
}

Future<SelectedUploadFile?> recoverLostAvatarFile() async {
  return null;
}

class _WebSelectedAvatarFile extends SelectedUploadFile {
  _WebSelectedAvatarFile(this._file);

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
        const FormatException('Unable to read the selected avatar file.'),
      );
    });

    errorSubscription = reader.onError.listen((_) {
      cleanup();
      completer.completeError(
        StateError('Unable to read the selected avatar file.'),
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
    default:
      return 'application/octet-stream';
  }
}
