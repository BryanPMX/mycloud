import 'dart:math';

import '../selected_upload_file.dart';

/// One account owns both the staged file and every remote multipart request.
class UploadCheckpoint {
  UploadCheckpoint(
      {required this.id,
      required this.ownerId,
      required this.file,
      required this.createdAt,
      this.mediaId,
      this.uploadId,
      this.partSize = 0,
      Map<int, String>? parts,
      this.sourceKey,
      this.wifiOnly = false,
      this.finalized = false,
      this.manuallyPaused = false,
      this.failures = 0})
      : parts = parts ?? {};
  final String id;
  final String ownerId;
  final SelectedUploadFile file;
  final DateTime createdAt;
  final String? sourceKey;
  bool wifiOnly;
  String? mediaId;
  String? uploadId;
  int partSize;
  final Map<int, String> parts;
  bool finalized;
  bool manuallyPaused;
  int failures;

  static String newId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  Map<String, Object?> toJson() => {
        'version': 1,
        'id': id,
        'owner_id': ownerId,
        'filename': file.name,
        'mime_type': file.mimeType,
        'size_bytes': file.sizeBytes,
        'created_at': createdAt.toIso8601String(),
        'media_id': mediaId,
        'upload_id': uploadId,
        'part_size': partSize,
        'parts': parts.map((key, value) => MapEntry('$key', value)),
        'source_key': sourceKey,
        'wifi_only': wifiOnly,
        'finalized': finalized,
        'manually_paused': manuallyPaused,
        'failures': failures,
      };
}
