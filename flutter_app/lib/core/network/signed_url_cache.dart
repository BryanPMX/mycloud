class SignedUrlCache {
  SignedUrlCache({
    required Duration refreshLeeway,
    DateTime Function()? clock,
  })  : _refreshLeeway = refreshLeeway,
        _clock = clock ?? DateTime.now;

  final Duration _refreshLeeway;
  final DateTime Function() _clock;
  final Map<String, SignedUrlCacheEntry> _entries =
      <String, SignedUrlCacheEntry>{};

  bool get isEmpty => _entries.isEmpty;

  String? urlFor(String cacheKey) {
    return _entries[_normalizeKey(cacheKey)]?.url;
  }

  bool needsRefresh(String cacheKey) {
    final normalizedKey = _normalizeKey(cacheKey);
    if (normalizedKey.isEmpty) {
      return false;
    }

    final entry = _entries[normalizedKey];
    if (entry == null) {
      return true;
    }

    return _clock().toUtc().isAfter(
          entry.expiresAt.subtract(_refreshLeeway),
        );
  }

  bool remember(
    String cacheKey,
    String? url, {
    required DateTime expiresAt,
  }) {
    final normalizedKey = _normalizeKey(cacheKey);
    if (normalizedKey.isEmpty) {
      return false;
    }

    final nextEntry = SignedUrlCacheEntry(
      url: _normalizeUrl(url),
      expiresAt: expiresAt.toUtc(),
    );
    final previousEntry = _entries[normalizedKey];
    if (previousEntry == nextEntry) {
      return false;
    }

    _entries[normalizedKey] = nextEntry;
    return true;
  }

  bool invalidate(String cacheKey) {
    return _entries.remove(_normalizeKey(cacheKey)) != null;
  }

  void clear() {
    _entries.clear();
  }

  String _normalizeKey(String cacheKey) {
    return cacheKey.trim();
  }

  String? _normalizeUrl(String? url) {
    final normalizedUrl = url?.trim();
    if (normalizedUrl == null || normalizedUrl.isEmpty) {
      return null;
    }

    return normalizedUrl;
  }
}

class SignedUrlCacheEntry {
  const SignedUrlCacheEntry({
    required this.url,
    required this.expiresAt,
  });

  final String? url;
  final DateTime expiresAt;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }

    return other is SignedUrlCacheEntry &&
        other.url == url &&
        other.expiresAt == expiresAt;
  }

  @override
  int get hashCode => Object.hash(url, expiresAt);
}
