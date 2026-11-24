import '../domain/photo_library.dart';

PhotoLibrary createPhotoLibrary() => UnavailablePhotoLibrary();

class UnavailablePhotoLibrary implements PhotoLibrary {
  @override
  bool get supported => false;
  @override
  Future<PhotoAccess> permission({bool request = false}) async =>
      PhotoAccess.denied;
  @override
  Future<List<DeviceAlbum>> albums() async => [];
  @override
  Future<List<DevicePhoto>> page(String albumId, int page, int size) async =>
      [];
  @override
  Future<bool> canTransfer({required bool wifiOnly}) async => false;
  @override
  Future<void> observe(void Function() changed) async {}
  @override
  Future<void> stopObserving() async {}
}
