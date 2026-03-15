import 'selected_upload_file.dart';
import 'upload_picker_io.dart'
    if (dart.library.html) 'upload_picker_web.dart' as platform_picker;

Future<List<SelectedUploadFile>> pickUploadFiles() =>
    platform_picker.pickUploadFiles();

bool get supportsUploadPicking => platform_picker.supportsUploadPicking;
