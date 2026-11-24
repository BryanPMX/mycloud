import 'package:familycloud/features/backup/domain/photo_library.dart';

class FakeLibrary implements PhotoLibrary {
  PhotoAccess access = PhotoAccess.full;
  bool online = true;
  int permissionCalls = 0, pageCalls = 0;
  List<DevicePhoto> photos = [];
  @override
  bool get supported => true;
  @override
  Future<PhotoAccess> permission({bool request = false}) async {
    permissionCalls++;
    return access;
  }

  @override
  Future<List<DeviceAlbum>> albums() async => access == PhotoAccess.limited
      ? [const DeviceAlbum('__allowed__', 'Photos you allow')]
      : [const DeviceAlbum('a', 'Camera'), const DeviceAlbum('b', 'Trips')];
  @override
  Future<List<DevicePhoto>> page(String id, int page, int size) async {
    pageCalls++;
    return photos;
  }

  @override
  Future<bool> canTransfer({required bool wifiOnly}) async => online;
  @override
  Future<void> observe(void Function() changed) async {}
  @override
  Future<void> stopObserving() async {}
}
