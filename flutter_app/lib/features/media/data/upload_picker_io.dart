import 'selected_upload_file.dart';

const bool supportsUploadPicking = false;

Future<List<SelectedUploadFile>> pickUploadFiles() {
  throw UnsupportedError(
    'File picking is currently implemented for Flutter web only.',
  );
}
