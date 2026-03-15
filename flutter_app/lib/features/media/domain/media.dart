enum MediaStatus {
  pending,
  ready,
  failed;

  static MediaStatus fromApi(Object? value) {
    switch (value) {
      case 'ready':
        return MediaStatus.ready;
      case 'failed':
        return MediaStatus.failed;
      default:
        return MediaStatus.pending;
    }
  }
}

class ThumbUrls {
  const ThumbUrls({this.small, this.medium, this.large, this.poster});

  final String? small;
  final String? medium;
  final String? large;
  final String? poster;

  factory ThumbUrls.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const ThumbUrls();
    }

    return ThumbUrls(
      small: json['small'] as String?,
      medium: json['medium'] as String?,
      large: json['large'] as String?,
      poster: json['poster'] as String?,
    );
  }
}

class Media {
  const Media({
    required this.id,
    required this.ownerId,
    required this.filename,
    required this.mimeType,
    required this.sizeBytes,
    required this.width,
    required this.height,
    required this.durationSecs,
    required this.status,
    required this.isFavorite,
    required this.uploadedAt,
    required this.thumbUrls,
    this.takenAt,
    this.deletedAt,
    this.purgesAt,
  });

  final String id;
  final String ownerId;
  final String filename;
  final String mimeType;
  final int sizeBytes;
  final int width;
  final int height;
  final double durationSecs;
  final MediaStatus status;
  final bool isFavorite;
  final DateTime? takenAt;
  final DateTime uploadedAt;
  final DateTime? deletedAt;
  final DateTime? purgesAt;
  final ThumbUrls thumbUrls;

  bool get isImage => mimeType.startsWith('image/');

  bool get isVideo => mimeType.startsWith('video/');

  double get aspectRatio {
    if (width == 0 || height == 0) {
      return 4 / 3;
    }
    return width / height;
  }

  Media copyWith({
    bool? isFavorite,
    MediaStatus? status,
    ThumbUrls? thumbUrls,
  }) {
    return Media(
      id: id,
      ownerId: ownerId,
      filename: filename,
      mimeType: mimeType,
      sizeBytes: sizeBytes,
      width: width,
      height: height,
      durationSecs: durationSecs,
      status: status ?? this.status,
      isFavorite: isFavorite ?? this.isFavorite,
      takenAt: takenAt,
      uploadedAt: uploadedAt,
      deletedAt: deletedAt,
      purgesAt: purgesAt,
      thumbUrls: thumbUrls ?? this.thumbUrls,
    );
  }

  factory Media.fromJson(Map<String, dynamic> json) {
    return Media(
      id: json['id'] as String? ?? '',
      ownerId: json['owner_id'] as String? ?? '',
      filename: json['filename'] as String? ?? '',
      mimeType: json['mime_type'] as String? ?? '',
      sizeBytes: _asInt(json['size_bytes']),
      width: _asInt(json['width']),
      height: _asInt(json['height']),
      durationSecs: _asDouble(json['duration_secs']),
      status: MediaStatus.fromApi(json['status']),
      isFavorite: json['is_favorite'] as bool? ?? false,
      takenAt: _parseDateTime(json['taken_at']),
      uploadedAt: _parseDateTime(json['uploaded_at']) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      deletedAt: _parseDateTime(json['deleted_at']),
      purgesAt: _parseDateTime(json['purges_at']),
      thumbUrls:
          ThumbUrls.fromJson(json['thumb_urls'] as Map<String, dynamic>?),
    );
  }

  static int _asInt(Object? value) {
    if (value is num) {
      return value.toInt();
    }

    return 0;
  }

  static double _asDouble(Object? value) {
    if (value is num) {
      return value.toDouble();
    }

    return 0;
  }

  static DateTime? _parseDateTime(Object? value) {
    if (value is String && value.trim().isNotEmpty) {
      return DateTime.tryParse(value);
    }

    return null;
  }
}
