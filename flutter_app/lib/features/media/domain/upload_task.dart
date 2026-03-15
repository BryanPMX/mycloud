enum MediaUploadStage {
  queued('Queued'),
  initializing('Starting'),
  uploading('Uploading'),
  processing('Processing'),
  complete('Ready'),
  failed('Failed'),
  cancelled('Cancelled');

  const MediaUploadStage(this.label);

  final String label;

  bool get isTerminal =>
      this == MediaUploadStage.complete ||
      this == MediaUploadStage.failed ||
      this == MediaUploadStage.cancelled;
}

class MediaUploadTask {
  const MediaUploadTask({
    required this.localId,
    required this.filename,
    required this.mimeType,
    required this.sizeBytes,
    required this.createdAt,
    required this.stage,
    required this.progress,
    this.mediaId,
    this.completedParts = 0,
    this.totalParts = 0,
    this.message,
  });

  final String localId;
  final String filename;
  final String mimeType;
  final int sizeBytes;
  final DateTime createdAt;
  final MediaUploadStage stage;
  final double progress;
  final String? mediaId;
  final int completedParts;
  final int totalParts;
  final String? message;

  bool get isTerminal => stage.isTerminal;

  bool get canCancel =>
      stage == MediaUploadStage.initializing ||
      stage == MediaUploadStage.uploading;

  bool get canDismiss => isTerminal;

  MediaUploadTask copyWith({
    MediaUploadStage? stage,
    double? progress,
    String? mediaId,
    int? completedParts,
    int? totalParts,
    String? message,
  }) {
    return MediaUploadTask(
      localId: localId,
      filename: filename,
      mimeType: mimeType,
      sizeBytes: sizeBytes,
      createdAt: createdAt,
      stage: stage ?? this.stage,
      progress: progress ?? this.progress,
      mediaId: mediaId ?? this.mediaId,
      completedParts: completedParts ?? this.completedParts,
      totalParts: totalParts ?? this.totalParts,
      message: message ?? this.message,
    );
  }
}
