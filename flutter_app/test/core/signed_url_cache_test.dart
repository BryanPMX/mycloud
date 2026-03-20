import 'package:familycloud/core/network/signed_url_cache.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('remember stores URLs and refreshes after the configured leeway', () {
    var now = DateTime.utc(2026, 3, 20, 19, 0);
    final cache = SignedUrlCache(
      refreshLeeway: const Duration(seconds: 30),
      clock: () => now,
    );

    expect(cache.needsRefresh('media-1'), isTrue);

    final changed = cache.remember(
      'media-1',
      'https://signed.example/thumb-1',
      expiresAt: DateTime.utc(2026, 3, 20, 19, 5),
    );

    expect(changed, isTrue);
    expect(cache.urlFor('media-1'), 'https://signed.example/thumb-1');
    expect(cache.needsRefresh('media-1'), isFalse);

    now = DateTime.utc(2026, 3, 20, 19, 4, 31);
    expect(cache.needsRefresh('media-1'), isTrue);
  });

  test('invalidate clears cached URLs', () {
    final cache = SignedUrlCache(
      refreshLeeway: Duration.zero,
    );

    cache.remember(
      'user-1',
      'https://signed.example/avatar-1',
      expiresAt: DateTime.utc(2026, 3, 20, 19, 5),
    );

    expect(cache.invalidate('user-1'), isTrue);
    expect(cache.urlFor('user-1'), isNull);
    expect(cache.needsRefresh('user-1'), isTrue);
  });
}
