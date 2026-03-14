enum MediaStatus { pending, ready, failed }

class ThumbUrls {
  const ThumbUrls({this.small, this.medium, this.large, this.poster});

  final String? small;
  final String? medium;
  final String? large;
  final String? poster;
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
  final int durationSecs;
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
}
