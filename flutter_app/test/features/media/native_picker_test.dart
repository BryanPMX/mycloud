import 'package:familycloud/features/media/data/upload_picker_io.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

class _Picker extends ImagePicker {
  _Picker({this.failure});
  final Object? failure;
  int singleCalls = 0;

  @override
  Future<List<XFile>> pickMultipleMedia({
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    int? limit,
    bool requestFullMetadata = true,
  }) async {
    if (failure != null) throw failure!;
    return [];
  }

  @override
  Future<XFile?> pickMedia({
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    bool requestFullMetadata = true,
  }) async {
    singleCalls++;
    return null;
  }
}

void main() {
  test('cancelling native multi-selection does not reopen a picker', () async {
    final picker = _Picker();
    expect(await pickUploadFiles(picker: picker), isEmpty);
    expect(picker.singleCalls, 0);
  });

  test('unsupported mixed selection falls back once', () async {
    for (final failure in [UnsupportedError('mixed'), UnimplementedError()]) {
      final picker = _Picker(failure: failure);
      expect(await pickUploadFiles(picker: picker), isEmpty);
      expect(picker.singleCalls, 1);
    }
  });

  test('permission denial and native errors do not trigger another picker',
      () async {
    final picker =
        _Picker(failure: PlatformException(code: 'photo_access_denied'));
    await expectLater(
        pickUploadFiles(picker: picker), throwsA(isA<PlatformException>()));
    expect(picker.singleCalls, 0);
  });
}
