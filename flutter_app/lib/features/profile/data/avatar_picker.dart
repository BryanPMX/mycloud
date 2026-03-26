import '../../media/data/selected_upload_file.dart';
import 'avatar_picker_io.dart' if (dart.library.html) 'avatar_picker_web.dart'
    as platform_picker;

typedef AvatarFilePicker = Future<SelectedUploadFile?> Function();

typedef LostAvatarFileRetriever = Future<SelectedUploadFile?> Function();

Future<SelectedUploadFile?> pickAvatarFile() =>
    platform_picker.pickAvatarFile();

Future<SelectedUploadFile?> recoverLostAvatarFile() =>
    platform_picker.recoverLostAvatarFile();

bool get supportsAvatarPicking => platform_picker.supportsAvatarPicking;
