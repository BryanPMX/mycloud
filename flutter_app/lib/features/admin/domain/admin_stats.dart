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
}
