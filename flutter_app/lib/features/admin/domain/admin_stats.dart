class AdminStats {
  const AdminStats({
    required this.totalUsers,
    required this.activeUsers,
    required this.totalBytes,
    required this.usedBytes,
    required this.totalItems,
    required this.totalImages,
    required this.totalVideos,
    required this.pendingJobs,
  });

  final int totalUsers;
  final int activeUsers;
  final int totalBytes;
  final int usedBytes;
  final int totalItems;
  final int totalImages;
  final int totalVideos;
  final int pendingJobs;

  int get freeBytes => totalBytes - usedBytes;

  double get pctUsed => totalBytes == 0 ? 0 : usedBytes / totalBytes;

  factory AdminStats.fromJson(Map<String, dynamic> json) {
    final users = json['users'] as Map<String, dynamic>? ?? const {};
    final storage = json['storage'] as Map<String, dynamic>? ?? const {};
    final media = json['media'] as Map<String, dynamic>? ?? const {};

    return AdminStats(
      totalUsers: _asInt(users['total']),
      activeUsers: _asInt(users['active']),
      totalBytes: _asInt(storage['total_bytes']),
      usedBytes: _asInt(storage['used_bytes']),
      totalItems: _asInt(media['total_items']),
      totalImages: _asInt(media['total_images']),
      totalVideos: _asInt(media['total_videos']),
      pendingJobs: _asInt(media['pending_jobs']),
    );
  }

  static int _asInt(Object? value) {
    if (value is num) {
      return value.toInt();
    }

    return 0;
  }
}
