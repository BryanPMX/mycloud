import 'selected_upload_file.dart';
import 'upload_picker_io.dart' if (dart.library.html) 'upload_picker_web.dart'
    as platform_picker;

typedef UploadFilesPicker = Future<List<SelectedUploadFile>> Function();

typedef LostUploadFilesRetriever = Future<List<SelectedUploadFile>> Function();

Future<List<SelectedUploadFile>> pickUploadFiles() =>
    platform_picker.pickUploadFiles();

Future<List<SelectedUploadFile>> recoverLostUploadFiles() =>
    platform_picker.recoverLostUploadFiles();

bool get supportsUploadPicking => platform_picker.supportsUploadPicking;
