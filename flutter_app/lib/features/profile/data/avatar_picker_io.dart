import 'package:image_picker/image_picker.dart';

import '../../media/data/selected_upload_file.dart';
import '../../media/data/xfile_selected_upload_file.dart';

const bool supportsAvatarPicking = true;

final ImagePicker _picker = ImagePicker();

Future<SelectedUploadFile?> pickAvatarFile() async {
  final file = await _picker.pickImage(source: ImageSource.gallery);
  if (file == null) {
    return null;
  }

  return selectedUploadFileFromXFile(file);
}

Future<SelectedUploadFile?> recoverLostAvatarFile() async {
  try {
    final response = await _picker.retrieveLostData();
    if (response.isEmpty) {
      return null;
    }

    final file = response.file ??
        ((response.files?.isNotEmpty ?? false) ? response.files!.first : null);
    if (file == null) {
      return null;
    }

    return selectedUploadFileFromXFile(file);
  } on UnimplementedError {
    return null;
  }
}
