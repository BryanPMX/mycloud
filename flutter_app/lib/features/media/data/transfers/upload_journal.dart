import '../selected_upload_file.dart';
import 'upload_checkpoint.dart';

abstract interface class UploadJournal {
  bool get persistent;
  Future<UploadCheckpoint> stage(
      {required String ownerId,
      required SelectedUploadFile file,
      String? sourceKey,
      bool wifiOnly = false});
  Future<List<UploadCheckpoint>> load(String ownerId);
  Future<void> save(UploadCheckpoint checkpoint);
  Future<void> remove(UploadCheckpoint checkpoint);
  Future<void> clearOwner(String ownerId);
  Future<Set<String>> completedSources(String ownerId);
  Future<void> complete(UploadCheckpoint checkpoint);
}

class MemoryUploadJournal implements UploadJournal {
  final Map<String, UploadCheckpoint> _items = {};
  final Map<String, Set<String>> _completed = {};
  @override
  bool get persistent => false;
  @override
  Future<UploadCheckpoint> stage(
      {required String ownerId,
      required SelectedUploadFile file,
      String? sourceKey,
      bool wifiOnly = false}) async {
    final checkpoint = UploadCheckpoint(
        id: UploadCheckpoint.newId(),
        ownerId: ownerId,
        file: file,
        createdAt: DateTime.now().toUtc(),
        sourceKey: sourceKey,
        wifiOnly: wifiOnly);
    _items[checkpoint.id] = checkpoint;
    return checkpoint;
  }

  @override
  Future<List<UploadCheckpoint>> load(String ownerId) async =>
      _items.values.where((item) => item.ownerId == ownerId).toList();
  @override
  Future<void> save(UploadCheckpoint checkpoint) async {
    _items[checkpoint.id] = checkpoint;
  }

  @override
  Future<void> remove(UploadCheckpoint checkpoint) async {
    _items.remove(checkpoint.id);
  }

  @override
  Future<void> clearOwner(String ownerId) async {
    _items.removeWhere((_, item) => item.ownerId == ownerId);
  }

  @override
  Future<Set<String>> completedSources(String ownerId) async =>
      Set.of(_completed[ownerId] ?? {});
  @override
  Future<void> complete(UploadCheckpoint checkpoint) async {
    if (checkpoint.sourceKey != null) {
      (_completed[checkpoint.ownerId] ??= {}).add(checkpoint.sourceKey!);
    }
    await remove(checkpoint);
  }
}
