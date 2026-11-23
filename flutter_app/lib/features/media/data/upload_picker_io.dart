import 'package:image_picker/image_picker.dart';

import 'selected_upload_file.dart';
import 'xfile_selected_upload_file.dart';

const bool supportsUploadPicking = true;

final ImagePicker _picker = ImagePicker();

Future<List<SelectedUploadFile>> pickUploadFiles({ImagePicker? picker}) async {
  final mediaPicker = picker ?? _picker;
  try {
    // An empty result is cancellation, not a reason to open another picker.
    return _wrapFiles(await mediaPicker.pickMultipleMedia());
  } on UnsupportedError {
    // Includes UnimplementedError on older native implementations.
  }

  final single = await mediaPicker.pickMedia();
  if (single == null) {
    return const <SelectedUploadFile>[];
  }

  return _wrapFiles(<XFile>[single]);
}

Future<List<SelectedUploadFile>> recoverLostUploadFiles() async {
  try {
    final response = await _picker.retrieveLostData();
    if (response.isEmpty) {
      return const <SelectedUploadFile>[];
    }

    final files = response.files;
    if (files != null && files.isNotEmpty) {
      return _wrapFiles(files);
    }

    final file = response.file;
    if (file == null) {
      return const <SelectedUploadFile>[];
    }

    return _wrapFiles(<XFile>[file]);
  } on UnimplementedError {
    return const <SelectedUploadFile>[];
  }
}

List<SelectedUploadFile> _wrapFiles(List<XFile> files) {
  return files
      .map<SelectedUploadFile>(selectedUploadFileFromXFile)
      .toList(growable: false);
}
