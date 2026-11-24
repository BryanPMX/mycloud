import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:photo_manager/photo_manager.dart';
import '../../media/data/xfile_selected_upload_file.dart';
import '../domain/photo_library.dart';
import 'photo_library_stub.dart';

PhotoLibrary createPhotoLibrary() => Platform.isIOS || Platform.isAndroid
    ? NativePhotoLibrary()
    : UnavailablePhotoLibrary();

class NativePhotoLibrary implements PhotoLibrary {
  void Function(MethodCall)? _callback;
  @override
  bool get supported => true;
  @override
  Future<PhotoAccess> permission({bool request = false}) async {
    final state = request
        ? await PhotoManager.requestPermissionExtend()
        : await PhotoManager.getPermissionState(
            requestOption: const PermissionRequestOption());
    return state.isAuth
        ? PhotoAccess.full
        : state.hasAccess
            ? PhotoAccess.limited
            : PhotoAccess.denied;
  }

  @override
  Future<List<DeviceAlbum>> albums() async {
    final access = await permission();
    if (access == PhotoAccess.denied) return [];
    if (access == PhotoAccess.limited) {
      return [const DeviceAlbum('__allowed__', 'Photos you allow')];
    }
    final paths = await PhotoManager.getAssetPathList(
        hasAll: false, type: RequestType.common);
    return paths
        .where((p) =>
            p.albumTypeEx?.darwin?.subtype !=
            PMDarwinAssetCollectionSubtype.smartAlbumAllHidden)
        .map((p) => DeviceAlbum(p.id, p.name))
        .toList();
  }

  @override
  Future<List<DevicePhoto>> page(String albumId, int page, int size) async {
    final access = await permission();
    if (access == PhotoAccess.denied) return [];
    if (access == PhotoAccess.limited && albumId != '__allowed__') return [];
    // The limited-access pseudo album must never expand into the whole library
    // when the OS permission changes to full access.
    if (access != PhotoAccess.limited && albumId == '__allowed__') return [];
    final paths = await PhotoManager.getAssetPathList(
        hasAll: albumId == '__allowed__',
        onlyAll: albumId == '__allowed__',
        type: RequestType.common);
    final album = albumId == '__allowed__'
        ? paths.firstOrNull
        : paths.where((a) => a.id == albumId).firstOrNull;
    if (album == null) return [];
    final assets = await album.getAssetListPaged(page: page, size: size);
    return assets
        .map((asset) => DevicePhoto(
            key:
                'photo:${asset.id}:${asset.modifiedDateTime.toUtc().millisecondsSinceEpoch}',
            createdAt: asset.createDateTime.toUtc(),
            isVideo: asset.type == AssetType.video,
            supported: !asset.isLivePhoto &&
                (asset.type == AssetType.image ||
                    asset.type == AssetType.video),
            open: () async {
              final file = await asset.originFile;
              if (file == null) return null;
              final title = await asset.titleAsync;
              final mime = await asset.mimeTypeAsync;
              return selectedUploadFileFromXFile(
                  XFile(file.path, name: title, mimeType: mime));
            }))
        .toList();
  }

  @override
  Future<bool> canTransfer({required bool wifiOnly}) async {
    final states = await Connectivity().checkConnectivity();
    if (wifiOnly) {
      return states.contains(ConnectivityResult.wifi);
    }
    return states.any((state) => state != ConnectivityResult.none);
  }

  @override
  Future<void> observe(void Function() changed) async {
    await stopObserving();
    _callback = (_) => changed();
    PhotoManager.addChangeCallback(_callback!);
    await PhotoManager.startChangeNotify();
  }

  @override
  Future<void> stopObserving() async {
    if (_callback != null) PhotoManager.removeChangeCallback(_callback!);
    _callback = null;
  }
}
