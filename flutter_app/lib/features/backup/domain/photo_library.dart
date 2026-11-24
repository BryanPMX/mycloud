import '../../media/data/selected_upload_file.dart';

enum PhotoAccess { denied, limited, full }

class DeviceAlbum {
  const DeviceAlbum(this.id, this.name);
  final String id;
  final String name;
}

class DevicePhoto {
  const DevicePhoto(
      {required this.key,
      required this.createdAt,
      required this.isVideo,
      required this.open,
      this.supported = true});
  final String key;
  final DateTime createdAt;
  final bool isVideo;
  final bool supported;
  final Future<SelectedUploadFile?> Function() open;
}

abstract interface class PhotoLibrary {
  bool get supported;
  Future<PhotoAccess> permission({bool request = false});
  Future<List<DeviceAlbum>> albums();
  Future<List<DevicePhoto>> page(String albumId, int page, int size);
  Future<bool> canTransfer({required bool wifiOnly});
  Future<void> observe(void Function() changed);
  Future<void> stopObserving();
}
