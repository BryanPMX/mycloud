class UploadProgressEvent {
  const UploadProgressEvent({
    required this.type,
    required this.mediaId,
    this.status,
    this.reason,
    this.thumbKeys,
  });

  final UploadProgressEventType type;
  final String mediaId;
  final String? status;
  final String? reason;
  final UploadProgressThumbKeys? thumbKeys;

  factory UploadProgressEvent.fromJson(Map<String, dynamic> json) {
    final type = UploadProgressEventType.fromApi(json['type']);
    final mediaId = (json['media_id'] as String? ?? '').trim();
    if (type == null || mediaId.isEmpty) {
      throw const FormatException('Invalid upload progress event.');
    }

    final thumbKeys = UploadProgressThumbKeys.fromJson(
      json['thumb_urls'] as Map<String, dynamic>?,
    );

    return UploadProgressEvent(
      type: type,
      mediaId: mediaId,
      status: (json['status'] as String?)?.trim(),
      reason: (json['reason'] as String?)?.trim(),
      thumbKeys: thumbKeys.isEmpty ? null : thumbKeys,
    );
  }
}

enum UploadProgressEventType {
  processingStarted,
  processingComplete,
  processingFailed;

  static UploadProgressEventType? fromApi(Object? value) {
    switch (value) {
      case 'processing_started':
        return UploadProgressEventType.processingStarted;
      case 'processing_complete':
        return UploadProgressEventType.processingComplete;
      case 'processing_failed':
        return UploadProgressEventType.processingFailed;
      default:
        return null;
    }
  }
}

class UploadProgressThumbKeys {
  const UploadProgressThumbKeys({
    this.small,
    this.medium,
    this.large,
    this.poster,
  });

  final String? small;
  final String? medium;
  final String? large;
  final String? poster;

  bool get isEmpty =>
      small == null && medium == null && large == null && poster == null;

  factory UploadProgressThumbKeys.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const UploadProgressThumbKeys();
    }

    return UploadProgressThumbKeys(
      small: _nonEmptyString(json['small']),
      medium: _nonEmptyString(json['medium']),
      large: _nonEmptyString(json['large']),
      poster: _nonEmptyString(json['poster']),
    );
  }
}

String? _nonEmptyString(Object? value) {
  final candidate = (value as String?)?.trim();
  return candidate == null || candidate.isEmpty ? null : candidate;
}
