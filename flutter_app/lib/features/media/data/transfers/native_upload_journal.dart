import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../selected_upload_file.dart';
import 'upload_checkpoint.dart';
import 'upload_journal.dart';

/// Private, bounded staging; filenames/URLs/tokens never become filesystem paths.
class NativeUploadJournal implements UploadJournal {
  NativeUploadJournal(
      {Future<Directory> Function()? directory,
      Future<void> Function(String)? protect})
      : _directory = directory ?? getApplicationSupportDirectory,
        _protect = protect ?? _protectOnIOS;
  final Future<Directory> Function() _directory;
  final Future<void> Function(String) _protect;
  Future<void> _tail = Future.value();
  static const maxStagedBytes = 1024 * 1024 * 1024;
  static const maxRecords = 100;
  static final _taskId = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');
  @override
  bool get persistent => true;

  static Future<void> _protectOnIOS(String path) async {
    if (Platform.isIOS) {
      await const MethodChannel('live.mynube.app/private_uploads')
          .invokeMethod<void>('protect', {'path': path});
    }
  }

  Future<T> _serial<T>(Future<T> Function() action) {
    final future = _tail.then((_) => action());
    _tail = future.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return future;
  }

  String _safe(String value) {
    if (!RegExp(r'^[a-zA-Z0-9_-]{1,128}$').hasMatch(value)) {
      throw const FormatException('Invalid upload identity.');
    }
    return value;
  }

  Future<Directory> _root() async {
    final root = Directory('${(await _directory()).path}/mynube-uploads');
    await root.create(recursive: true);
    await _protect(root.path);
    return root;
  }

  Future<Directory> _owner(String ownerId) async =>
      Directory('${(await _root()).path}/${_safe(ownerId)}');
  Future<Directory> _task(UploadCheckpoint checkpoint) async => Directory(
      '${(await _owner(checkpoint.ownerId)).path}/${_safe(checkpoint.id)}');
  Future<void> _write(File file, Map<String, Object?> data) async {
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(data), flush: true);
    await _protect(temporary.path);
    await temporary.rename(file.path);
  }

  @override
  Future<UploadCheckpoint> stage(
          {required String ownerId,
          required SelectedUploadFile file,
          String? sourceKey,
          bool wifiOnly = false}) =>
      _serial(() async {
        final size = await file.loadSizeBytes();
        if (size <= 0 || size > 512 * 1024 * 1024) {
          throw StateError('Choose a file no larger than 512 MB.');
        }
        final root = await _root();
        var used = 0;
        var count = 0;
        await for (final entity
            in root.list(recursive: true, followLinks: false)) {
          if (entity is File && entity.path.endsWith('/source')) {
            used += await entity.length();
            count++;
          }
        }
        if (used + size > maxStagedBytes || count >= maxRecords) {
          throw StateError(
              'Your upload queue is full. Finish or cancel some uploads first.');
        }
        final id = UploadCheckpoint.newId();
        final folder = Directory('${(await _owner(ownerId)).path}/$id');
        await folder.create(recursive: true);
        await _protect(folder.path);
        final source = File('${folder.path}/source');
        try {
          final output = await source.open(mode: FileMode.write);
          try {
            for (var start = 0; start < size; start += 5 * 1024 * 1024) {
              final end = math.min(size, start + 5 * 1024 * 1024);
              final bytes = await file.readChunk(start, end);
              if (bytes.length != end - start) {
                throw StateError('The selected file changed. Choose it again.');
              }
              await output.writeFrom(bytes);
            }
            await output.flush();
          } finally {
            await output.close();
          }
          await _protect(source.path);
          final staged = _StagedFile(source, file.name, file.mimeType, size);
          final checkpoint = UploadCheckpoint(
              id: id,
              ownerId: ownerId,
              file: staged,
              createdAt: DateTime.now().toUtc(),
              sourceKey: sourceKey,
              wifiOnly: wifiOnly);
          await _write(
              File('${folder.path}/checkpoint.json'), checkpoint.toJson());
          return checkpoint;
        } catch (_) {
          await folder.delete(recursive: true);
          rethrow;
        }
      });

  @override
  Future<void> save(UploadCheckpoint checkpoint) => _serial(() async {
        final folder = await _task(checkpoint);
        if (!await folder.exists()) {
          throw StateError('This upload was cancelled.');
        }
        await _write(
            File('${folder.path}/checkpoint.json'), checkpoint.toJson());
      });

  @override
  Future<List<UploadCheckpoint>> load(String ownerId) => _serial(() async {
        final owner = await _owner(ownerId);
        if (!await owner.exists()) return [];
        final checkpoints = <UploadCheckpoint>[];
        await for (final folder in owner.list(followLinks: false)) {
          if (folder is! Directory) continue;
          final metadata = File('${folder.path}/checkpoint.json');
          if (!await metadata.exists()) {
            // An uncommitted staging copy never reached the API. Removing only
            // this UUID folder cannot modify the phone original or a vault item.
            final name = folder.path.split(Platform.pathSeparator).last;
            if (_taskId.hasMatch(name)) {
              await folder.delete(recursive: true);
            }
            continue;
          }
          if (checkpoints.length >= maxRecords) {
            throw StateError('Upload queue requires attention.');
          }
          if (await metadata.length() > 256 * 1024) {
            throw const FormatException('Upload recovery requires attention.');
          }
          final data =
              jsonDecode(await metadata.readAsString()) as Map<String, dynamic>;
          final id = _safe(data['id'] as String);
          final size = data['size_bytes'] as int;
          final partSize = data['part_size'] as int;
          final parts = (data['parts'] as Map<String, dynamic>)
              .map((k, v) => MapEntry(int.parse(k), v as String));
          final initialized = data['upload_id'] != null;
          if (data['version'] != 1 ||
              !_taskId.hasMatch(id) ||
              data['owner_id'] != ownerId ||
              !folder.path.endsWith('/$id') ||
              size <= 0 ||
              size > 512 * 1024 * 1024 ||
              (initialized &&
                  (data['media_id'] != id ||
                      (data['upload_id'] as String).isEmpty ||
                      partSize <= 0)) ||
              (!initialized &&
                  (data['media_id'] != null ||
                      partSize != 0 ||
                      parts.isNotEmpty)) ||
              (data['finalized'] == true && !initialized) ||
              parts.entries.any((part) =>
                  part.key <= 0 ||
                  partSize <= 0 ||
                  part.key > (size / partSize).ceil() ||
                  part.value.isEmpty ||
                  part.value.length > 1024)) {
            throw const FormatException('Upload recovery requires attention.');
          }
          final source = File('${folder.path}/source');
          if (!await source.exists() || await source.length() != size) {
            throw StateError('A staged upload is unavailable.');
          }
          checkpoints.add(UploadCheckpoint(
              id: id,
              ownerId: ownerId,
              file: _StagedFile(source, data['filename'] as String,
                  data['mime_type'] as String, size),
              createdAt: DateTime.parse(data['created_at'] as String),
              mediaId: data['media_id'] as String?,
              uploadId: data['upload_id'] as String?,
              partSize: partSize,
              parts: parts,
              sourceKey: data['source_key'] as String?,
              wifiOnly: data['wifi_only'] as bool,
              finalized: data['finalized'] as bool,
              manuallyPaused: data['manually_paused'] as bool? ?? false,
              failures: data['failures'] as int? ?? 0));
        }
        return checkpoints;
      });
  @override
  Future<void> remove(UploadCheckpoint checkpoint) => _serial(() async {
        final folder = await _task(checkpoint);
        if (await folder.exists()) await folder.delete(recursive: true);
      });
  @override
  Future<void> clearOwner(String ownerId) => _serial(() async {
        final folder = await _owner(ownerId);
        if (await folder.exists()) {
          await for (final task in folder.list(followLinks: false)) {
            if (task is Directory) await task.delete(recursive: true);
          }
        }
      });

  Future<Map<String, dynamic>> _receipts(String ownerId) async {
    final file = File('${(await _owner(ownerId)).path}/receipts.json');
    if (!await file.exists()) return {};
    if (await file.length() > 32 * 1024 * 1024) {
      throw StateError('Backup history requires attention.');
    }
    return jsonDecode(await file.readAsString()) as Map<String, dynamic>;
  }

  @override
  Future<Set<String>> completedSources(String ownerId) =>
      _serial(() async => (await _receipts(ownerId)).keys.toSet());
  @override
  Future<void> complete(UploadCheckpoint checkpoint) => _serial(() async {
        if (checkpoint.sourceKey != null) {
          final receipts = await _receipts(checkpoint.ownerId);
          if (receipts.length >= 100000 &&
              !receipts.containsKey(checkpoint.sourceKey)) {
            throw StateError('Backup history is full.');
          }
          receipts[checkpoint.sourceKey!] = checkpoint.mediaId;
          if (utf8.encode(jsonEncode(receipts)).length > 32 * 1024 * 1024) {
            throw StateError('Backup history is full.');
          }
          await _write(
              File('${(await _owner(checkpoint.ownerId)).path}/receipts.json'),
              receipts);
        }
        final folder = await _task(checkpoint);
        if (await folder.exists()) await folder.delete(recursive: true);
      });
}

class _StagedFile extends SelectedUploadFile {
  const _StagedFile(this.source, this.name, this.mimeType, this.sizeBytes);
  final File source;
  @override
  final String name;
  @override
  final String mimeType;
  @override
  final int sizeBytes;
  @override
  Future<Uint8List> readChunk(int start, int end) async {
    if (start < 0 || end < start || end > sizeBytes) {
      throw RangeError('Invalid upload range.');
    }
    final handle = await source.open();
    try {
      await handle.setPosition(start);
      return await handle.read(end - start);
    } finally {
      await handle.close();
    }
  }
}
