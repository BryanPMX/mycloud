class BackupPreferences {
  const BackupPreferences(
      {this.enabled = false,
      this.albumIds = const {},
      this.includeExisting = false,
      this.includeVideos = true,
      this.wifiOnly = true,
      this.startedAt});
  final bool enabled;
  final Set<String> albumIds;
  final bool includeExisting;
  final bool includeVideos;
  final bool wifiOnly;
  final DateTime? startedAt;
  BackupPreferences copyWith(
          {bool? enabled,
          Set<String>? albumIds,
          bool? includeExisting,
          bool? includeVideos,
          bool? wifiOnly,
          DateTime? startedAt}) =>
      BackupPreferences(
          enabled: enabled ?? this.enabled,
          albumIds: albumIds ?? this.albumIds,
          includeExisting: includeExisting ?? this.includeExisting,
          includeVideos: includeVideos ?? this.includeVideos,
          wifiOnly: wifiOnly ?? this.wifiOnly,
          startedAt: startedAt ?? this.startedAt);
  Map<String, Object?> toJson() => {
        'v': 1,
        'enabled': enabled,
        'albums': albumIds.toList(),
        'include_existing': includeExisting,
        'include_videos': includeVideos,
        'wifi_only': wifiOnly,
        'started_at': startedAt?.toUtc().toIso8601String()
      };
  factory BackupPreferences.fromJson(Map<String, dynamic> data) {
    if (data['v'] != 1) {
      throw const FormatException('Unsupported backup settings.');
    }
    return BackupPreferences(
        enabled: data['enabled'] as bool,
        albumIds: (data['albums'] as List).cast<String>().toSet(),
        includeExisting: data['include_existing'] as bool,
        includeVideos: data['include_videos'] as bool,
        wifiOnly: data['wifi_only'] as bool,
        startedAt: DateTime.tryParse(data['started_at'] as String? ?? ''));
  }
}
