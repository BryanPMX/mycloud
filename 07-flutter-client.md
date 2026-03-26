# 07 — Flutter Client Architecture

Current implementation note on March 26, 2026:
- `flutter_app/` still uses the lightweight `ChangeNotifier` + custom `RouterDelegate` foundation, but it now goes beyond seeded placeholders: auth/session restore, secure native token persistence, media reads, comment create/delete, album create/edit/delete plus membership/share flows, profile display-name/avatar edits, non-admin directory-backed recipient picking, admin stats plus user-management screens, browser multipart uploads, native Android/iOS picking, and worker progress updates all hit the live Go API and WebSocket surfaces by default.
- `AppConfig` still targets `https://mynube.live` for the app, `https://api.mynube.live/api/v1` for REST, and `wss://api.mynube.live/ws/progress` for worker updates. `USE_DEMO_DATA` now defaults to `false`; enable it explicitly for smoke tests or offline UI work.
- The Flutter network layer now uses `package:http`, sends browser credentials on web for API calls, uses a second non-credentialed browser client for presigned MinIO part uploads, retries protected reads after `/auth/refresh`, and resolves presigned thumbnail URLs from `GET /media/:id/thumb`.
- `ConnectivityService` is now live instead of placeholder-only: it combines browser online/offline signals with transport-level reachability feedback, surfaces that status in the shell and upload UI, and now blocks favorites, comments, and album mutations in addition to upload/avatar actions when the backend is unreachable.
- The media picker is now split intentionally by platform: web still uses `FileUploadInputElement`, `Blob.slice`, and `FileReader.readAsArrayBuffer` so the browser can stream multipart chunks without another package, while Android/iOS now use `image_picker` with Android lost-data recovery and a single-media fallback for older iOS gallery behavior.
- Flutter now consumes `GET /users/directory` for album-recipient picking and caches signed avatar URLs by `user_id`. It seeds that cache from `/users/me`, `/users/directory`, comment authors, and share recipients, then refreshes stale entries through `GET /users/:id/avatar`. Media thumbnails now use the same TTL-aware signed-URL cache pattern against `GET /media/:id/thumb`.
- The backend now also implements the documented CORS path through `ALLOWED_ORIGINS`, which is required for the Flutter web app to call `api.mynube.live` with cookies/credentials.
- the release shell now uses a real app version (`1.0.0+1`), consistent consumer-facing `Mynube` branding, Android/iOS bundle ids rooted at `live.mynube.app`, Android release-keystore scaffolding via `android/key.properties`, and Xcode team id `55BP75778A` for automatic iOS signing
- `flutter analyze`, `flutter test`, `scripts/deploy-web.sh`, `flutter build ios --release --no-codesign`, `flutter build appbundle --release`, and `go test ./...` all pass for this slice. The `integration_test/` suite still runs on the local iOS simulator in this workspace, and the live-backend upload/reconnect variant remains checked in behind credential-based skipping.
- Confirmed production domain plan remains: `https://mynube.live` for the Flutter web app, `https://api.mynube.live` for the Go API, `https://minio.mynube.live` for presigned object traffic, and `https://console.mynube.live` for the MinIO console/admin surface.

Reference docs used for the current live integration slice:
- Flutter navigation overview: [docs.flutter.dev/ui/navigation](https://docs.flutter.dev/ui/navigation)
- `MaterialApp.router`: [api.flutter.dev/flutter/material/MaterialApp/MaterialApp.router.html](https://api.flutter.dev/flutter/material/MaterialApp/MaterialApp.router.html)
- Flutter networking cookbook: [docs.flutter.dev/cookbook/networking/authenticated-requests](https://docs.flutter.dev/cookbook/networking/authenticated-requests)
- Flutter integration testing guide: [docs.flutter.dev/testing/integration-tests](https://docs.flutter.dev/testing/integration-tests)
- Flutter integration testing concepts: [docs.flutter.dev/cookbook/testing/integration/introduction](https://docs.flutter.dev/cookbook/testing/integration/introduction)
- `image_picker` plugin: [pub.dev/packages/image_picker](https://pub.dev/packages/image_picker)
- Android Photo Picker: [developer.android.com/about/versions/13/features/photopicker](https://developer.android.com/about/versions/13/features/photopicker)
- Apple `PHPickerViewController`: [developer.apple.com/documentation/photosui/phpickerviewcontroller](https://developer.apple.com/documentation/photosui/phpickerviewcontroller)
- `showDialog`: [api.flutter.dev/flutter/material/showDialog.html](https://api.flutter.dev/flutter/material/showDialog.html)
- `TextEditingController`: [api.flutter.dev/flutter/widgets/TextEditingController-class.html](https://api.flutter.dev/flutter/widgets/TextEditingController-class.html)
- `package:http` browser credentials support: [pub.dev/documentation/http/latest/browser_client/BrowserClient-class.html](https://pub.dev/documentation/http/latest/browser_client/BrowserClient-class.html)
- `dart:io` `WebSocket.connect`: [api.dart.dev/dart-io/WebSocket/connect.html](https://api.dart.dev/dart-io/WebSocket/connect.html)
- `FileUploadInputElement.accept`: [api.dart.dev/dart-html/FileUploadInputElement/accept.html](https://api.dart.dev/dart-html/FileUploadInputElement/accept.html)
- `Blob.slice`: [api.dart.dev/dart-html/Blob/slice.html](https://api.dart.dev/dart-html/Blob/slice.html)
- `FileReader.readAsArrayBuffer`: [api.dart.dev/dart-html/FileReader/readAsArrayBuffer.html](https://api.dart.dev/dart-html/FileReader/readAsArrayBuffer.html)

---

## 1. Current Implemented Slice

```
lib/
├── main.dart                        # Widgets binding + AppConfig bootstrap
├── app.dart                         # MaterialApp.router + controller composition
├── core/
│   ├── config/app_config.dart       # APP_BASE_URL / API_BASE_URL / WS_BASE_URL
│   ├── network/api_client.dart      # Endpoint builder for the live backend
│   ├── network/api_transport.dart   # Shared JSON transport + raw PUT support
│   ├── network/http_client_factory* # Credentialed API client + direct-upload client selection
│   ├── router/app_router.dart       # RouterDelegate + auth restore loading state
│   ├── websocket/                   # Authenticated progress socket + message parsing
│   └── theme/app_theme.dart         # Material 3 theme and shell styling
├── features/
│   ├── auth/                        # Live login + refresh + native secure session restore
│   ├── media/                       # Live library reads, uploads, favorites, thumbs, and inline comment actions
│   ├── albums/                      # Live owned/shared album overview UI + album CRUD/share/membership dialogs
│   ├── directory/                   # Family directory reads + signed avatar URL cache keyed by user_id
│   ├── profile/                     # Endpoint/status + display-name/avatar editing UI
│   ├── admin/                       # Live stats, invites, and account-management UI
│   └── comments/                    # Live media comment reads + create/delete mutations
├── shared/
│   ├── widgets/main_scaffold.dart   # Adaptive rail/bottom-nav shell
│   ├── widgets/user_avatar.dart     # Shared user avatar renderer with signed-URL refresh
│   └── utils/                       # Date + file-size formatters
├── test/                            # Smoke, DTO parsing, connectivity, album, and directory/avatar-cache coverage
└── integration_test/                # Demo-mode end-to-end happy paths for admin/member flows
```

## 2. Current Dependency Set

```yaml
dependencies:
  flutter:
    sdk: flutter
  cupertino_icons: ^1.0.8
  flutter_secure_storage: ^10.0.0
  http: ^1.2.1
  image_picker: ^1.2.1

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^5.0.0
  integration_test:
    sdk: flutter
```

## 3. Recommended Next Flutter Continuation

1. Run `integration_test/live_backend_upload_reconnect_test.dart` with real backend credentials plus seeded upload-safe accounts so the new live variant exercises end-to-end uploads instead of skipping.
2. Install Apple Development/Distribution certificates in Xcode for team `55BP75778A`, then archive with `flutter build ipa` or Xcode Organizer so TestFlight/App Store upload becomes possible.
3. Generate the Android upload keystore from `flutter_app/android/key.properties.example`, switch to a signed `.aab`, and enroll the app in Play App Signing.
4. Propagate the same offline guard pattern into any remaining admin/directory-only flows that still rely on generic API failures instead of connectivity-aware messaging.

## 4. Target Architecture Reference

The rest of this document remains the broader target-state client plan. It is still useful for the eventual integration phase, but it is not a line-by-line description of the current `flutter_app/` implementation.

## 5. Target Project Structure

```
lib/
├── main.dart                        # App entry point, ProviderScope
├── app.dart                         # MaterialApp.router + theme
├── core/
│   ├── config/
│   │   └── app_config.dart          # Base URL, environment flags
│   ├── network/
│   │   ├── api_client.dart          # Dio instance, interceptors
│   │   ├── auth_interceptor.dart    # Auto-refresh JWT, retry on 401
│   │   └── error_handler.dart       # DioException → domain error
│   ├── storage/
│   │   └── secure_storage.dart      # flutter_secure_storage wrapper
│   ├── router/
│   │   └── app_router.dart          # go_router routes + guards
│   └── theme/
│       ├── app_theme.dart           # ThemeData (light + dark)
│       └── app_colors.dart
├── features/
│   ├── auth/
│   │   ├── data/
│   │   │   ├── auth_repository.dart
│   │   │   └── auth_dto.dart
│   │   ├── domain/
│   │   │   ├── auth_state.dart
│   │   │   └── user.dart
│   │   ├── providers/
│   │   │   └── auth_provider.dart   # Riverpod AsyncNotifier
│   │   └── ui/
│   │       ├── login_screen.dart
│   │       └── accept_invite_screen.dart
│   ├── media/
│   │   ├── data/
│   │   │   ├── media_repository.dart
│   │   │   ├── media_dto.dart
│   │   │   └── upload_manager.dart  # Chunked upload logic
│   │   ├── domain/
│   │   │   └── media.dart
│   │   ├── providers/
│   │   │   ├── media_list_provider.dart
│   │   │   ├── favorite_provider.dart
│   │   │   ├── trash_provider.dart
│   │   │   ├── upload_provider.dart
│   │   │   └── download_provider.dart
│   │   └── ui/
│   │       ├── photo_grid_screen.dart
│   │       ├── media_detail_screen.dart
│   │       ├── trash_screen.dart
│   │       ├── video_player_screen.dart
│   │       └── upload_sheet.dart
│   ├── albums/
│   │   ├── data/
│   │   │   └── album_repository.dart
│   │   ├── providers/
│   │   │   └── album_provider.dart
│   │   └── ui/
│   │       ├── album_list_screen.dart
│   │       ├── album_detail_screen.dart
│   │       └── share_album_sheet.dart
│   ├── profile/
│   │   └── ui/
│   │       ├── profile_screen.dart
│   │       └── storage_usage_widget.dart
│   └── admin/
│       └── ui/
│           ├── admin_dashboard_screen.dart
│           └── user_management_screen.dart
└── shared/
    ├── widgets/
    │   ├── thumbnail_image.dart     # Cached thumbnail with expiry-aware refresh
    │   ├── upload_progress_bar.dart
    │   ├── empty_state.dart
    │   ├── error_retry.dart
    │   └── shimmer_grid.dart
    └── utils/
        ├── file_size_formatter.dart
        └── date_formatter.dart
```

---

## 6. Planned Dependencies (Target State)

```yaml
dependencies:
  flutter:
    sdk: flutter

  # Networking
  dio: ^5.4.3                    # HTTP client
  web_socket_channel: ^2.4.0     # WebSocket for media processing status

  # State management
  flutter_riverpod: ^2.5.1
  riverpod_annotation: ^2.3.5

  # Navigation
  go_router: ^13.2.4

  # Storage & media access
  flutter_secure_storage: ^9.0.0 # Keychain/Keystore for tokens
  photo_manager: ^3.3.0          # Camera roll access (auto-backup)
  image_picker: ^1.1.2           # Manual file picker
  video_player: ^2.8.6           # In-app video playback
  chewie: ^1.8.1                 # Video player UI controls

  # Images
  cached_network_image: ^3.3.1   # LRU disk+memory cache for thumbnails
  photo_view: ^0.14.0            # Pinch-to-zoom fullscreen

  # Connectivity & background
  connectivity_plus: ^6.0.3
  workmanager: ^0.5.2            # Background auto-backup on Android/iOS

  # UI utilities
  shimmer: ^3.0.0                # Loading skeleton
  share_plus: ^9.0.0             # Native OS share sheet
  path_provider: ^2.1.3

dev_dependencies:
  riverpod_generator: ^2.4.0     # Code generation for providers
  build_runner: ^2.4.9
  flutter_lints: ^3.0.0
```

---

## 3. State Management (Riverpod)

All state is managed with Riverpod `AsyncNotifier` and `Notifier`. No `setState` anywhere except trivial local UI state.

### Auth Provider

```dart
// features/auth/providers/auth_provider.dart
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
part 'auth_provider.g.dart';

@riverpod
class AuthNotifier extends _$AuthNotifier {
  @override
  Future<User?> build() async {
    // On startup, try to restore the current session.
    // Mobile uses secure storage; web relies on httpOnly cookies.
    try {
      final repo = ref.read(authRepositoryProvider);
      return await repo.getCurrentUser();
    } catch (_) {
      if (!kIsWeb) {
        await ref.read(secureStorageProvider).clearTokens();
      }
      return null;
    }
  }

  Future<void> login(String email, String password) async {
    state = const AsyncLoading();
    final repo = ref.read(authRepositoryProvider);
    state = await AsyncValue.guard(() async {
      final result = await repo.login(email, password);
      if (!kIsWeb) {
        final storage = ref.read(secureStorageProvider);
        await storage.saveTokens(
          accessToken: result.accessToken,
          refreshToken: result.refreshToken,
        );
      }
      return result.user;
    });
  }

  Future<void> logout() async {
    try {
      final storage = ref.read(secureStorageProvider);
      final refreshToken = kIsWeb ? null : await storage.getRefreshToken();
      await ref.read(authRepositoryProvider).logout(refreshToken);
      if (!kIsWeb) {
        await storage.clearTokens();
      }
    } catch (_) {
      if (!kIsWeb) {
        await ref.read(secureStorageProvider).clearTokens();
      }
    }
    state = const AsyncData(null);
  }
}
```

### Media List Provider (Paginated)

```dart
// features/media/providers/media_list_provider.dart
@riverpod
class MediaListNotifier extends _$MediaListNotifier {
  String? _nextCursor;
  bool _hasMore = true;

  @override
  Future<List<Media>> build() async {
    _nextCursor = null;
    _hasMore = true;
    return _fetchPage();
  }

  Future<List<Media>> _fetchPage() async {
    final page = await ref.read(mediaRepositoryProvider).listMedia(
      cursor: _nextCursor,
      limit: 50,
    );
    _nextCursor = page.nextCursor;
    _hasMore = page.nextCursor.isNotEmpty;
    return page.items;
  }

  Future<void> loadMore() async {
    if (!_hasMore) return;
    if (state is AsyncLoading) return;

    final current = state.valueOrNull ?? [];
    state = AsyncData(current); // keep current data visible

    final more = await _fetchPage();
    state = AsyncData([...current, ...more]);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    _nextCursor = null;
    _hasMore = true;
    state = await AsyncValue.guard(_fetchPage);
  }

  // Called when a new upload completes
  void prependMedia(Media media) {
    final current = state.valueOrNull ?? [];
    state = AsyncData([media, ...current]);
  }
}
```

---

## 4. Auto-Refreshing Auth Interceptor

The Dio interceptor handles silent token refresh. If a request fails with 401, it refreshes the access token once and retries the original request.

```dart
// core/network/auth_interceptor.dart
import 'package:flutter/foundation.dart';

class AuthInterceptor extends Interceptor {
  final SecureStorage _storage;
  final AuthRepository _authRepo;
  final Dio _dio;
  bool _isRefreshing = false;
  final _pendingRequests = <Completer<void>>[];

  AuthInterceptor(this._storage, this._authRepo, this._dio);

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (kIsWeb) {
      options.extra['withCredentials'] = true;
      handler.next(options);
      return;
    }

    final token = await _storage.getAccessToken();
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    if (err.response?.statusCode != 401) {
      handler.next(err);
      return;
    }

    // Already tried refreshing — forward the 401
    if (err.requestOptions.extra['_retried'] == true) {
      handler.next(err);
      return;
    }

    if (_isRefreshing) {
      // Queue request until refresh completes
      final completer = Completer<void>();
      _pendingRequests.add(completer);
      await completer.future;
      err.requestOptions.extra['_retried'] = true;
      handler.resolve(await _retry(err.requestOptions));
      return;
    }

    _isRefreshing = true;
    try {
      if (kIsWeb) {
        await _authRepo.refreshToken(null); // refresh cookie is sent automatically
      } else {
        final refreshToken = await _storage.getRefreshToken();
        if (refreshToken == null) throw Exception('No refresh token');

        final result = await _authRepo.refreshToken(refreshToken);
        await _storage.saveTokens(
          accessToken: result.accessToken,
          refreshToken: result.refreshToken ?? refreshToken,
        );
      }

      // Release all queued requests
      for (final c in _pendingRequests) { c.complete(); }
      _pendingRequests.clear();

      err.requestOptions.extra['_retried'] = true;
      handler.resolve(await _retry(err.requestOptions));
    } catch (_) {
      // Refresh failed — clear tokens, redirect to login
      await _storage.clearTokens();
      for (final c in _pendingRequests) { c.completeError('auth_expired'); }
      _pendingRequests.clear();
      handler.next(err);
    } finally {
      _isRefreshing = false;
    }
  }

  Future<Response> _retry(RequestOptions options) {
    if (kIsWeb) {
      options.extra['withCredentials'] = true;
    }
    return _dio.fetch(options);
  }
}
```

---

## 5. Chunked Upload Manager

```dart
// features/media/data/upload_manager.dart
class UploadManager {
  static const int chunkSizeBytes = 5 * 1024 * 1024; // 5 MB

  final ApiClient _api;
  final UploadProgressHub _progressHub; // WebSocket

  Future<Media> upload(XFile file, {void Function(double)? onProgress}) async {
    final mimeType = lookupMimeType(file.path) ?? 'application/octet-stream';
    final fileSize = await file.length();

    // 1. Init multipart upload
    final init = await _api.post('/media/upload/init', body: {
      'filename':   file.name,
      'mime_type':  mimeType,
      'size_bytes': fileSize,
    });
    final mediaId  = init['media_id'] as String;
    final uploadId = init['upload_id'] as String;
    final totalParts = (fileSize / chunkSizeBytes).ceil();

    // 2. Upload chunks directly to MinIO using presigned part URLs.
    final parts = <Map<String, dynamic>>[];
    for (int part = 1; part <= totalParts; part++) {
      final start = (part - 1) * chunkSizeBytes;
      final end = (start + chunkSizeBytes > fileSize) ? fileSize : start + chunkSizeBytes;

      final presign = await _api.post('/media/upload/$mediaId/part-url', body: {
        'upload_id': uploadId,
        'part_number': part,
      });

      final response = await Dio().put(
        presign['url'] as String,
        data: file.openRead(start, end),
        options: Options(
          headers: {Headers.contentLengthHeader: '${end - start}'},
          responseType: ResponseType.plain,
        ),
        onSendProgress: (sent, _) {
          onProgress?.call((start + sent) / fileSize);
        },
      );

      parts.add({
        'part_number': part,
        'etag': response.headers.value('etag'),
      });
    }

    // 3. Complete upload
    final media = await _api.post('/media/upload/$mediaId/complete', body: {
      'upload_id': uploadId,
      'parts':     parts,
    });

    return Media.fromJson(media as Map<String, dynamic>);
  }

  Future<void> abort(String mediaId) async {
    await _api.delete('/media/upload/$mediaId');
  }
}
```

---

## 6. Navigation (go_router)

```dart
// core/router/app_router.dart
@riverpod
GoRouter appRouter(AppRouterRef ref) {
  final authState = ref.watch(authNotifierProvider);

  return GoRouter(
    initialLocation: '/media',
    redirect: (context, state) {
      final isLoggedIn = authState.valueOrNull != null;
      final isAuthRoute = state.matchedLocation.startsWith('/auth');

      if (!isLoggedIn && !isAuthRoute) return '/auth/login';
      if (isLoggedIn && isAuthRoute) return '/media';
      return null;
    },
    routes: [
      GoRoute(path: '/auth/login',   builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/auth/accept',  builder: (_, s)  => AcceptInviteScreen(token: s.uri.queryParameters['token']!)),
      ShellRoute(
        builder: (_, __, child) => MainScaffold(child: child),
        routes: [
          GoRoute(
            path: '/media',
            builder: (_, __) => const PhotoGridScreen(),
            routes: [
              GoRoute(
                path: ':id',
                builder: (_, s) => MediaDetailScreen(mediaId: s.pathParameters['id']!),
              ),
            ],
          ),
          GoRoute(
            path: '/albums',
            builder: (_, __) => const AlbumListScreen(),
            routes: [
              GoRoute(
                path: ':id',
                builder: (_, s) => AlbumDetailScreen(albumId: s.pathParameters['id']!),
              ),
            ],
          ),
          GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen()),
          GoRoute(path: '/admin',   builder: (_, __) => const AdminDashboardScreen()),
        ],
      ),
    ],
  );
}
```

---

## 7. Photo Grid (Performance Optimized)

```dart
// features/media/ui/photo_grid_screen.dart
class PhotoGridScreen extends ConsumerWidget {
  const PhotoGridScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mediaAsync = ref.watch(mediaListNotifierProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Family Cloud'),
        actions: [
          IconButton(
            icon: const Icon(Icons.upload),
            onPressed: () => _showUploadSheet(context),
          ),
        ],
      ),
      body: mediaAsync.when(
        loading: () => const ShimmerGrid(),
        error:   (e, _) => ErrorRetry(onRetry: () => ref.invalidate(mediaListNotifierProvider)),
        data:    (items) => _Grid(items: items),
      ),
    );
  }
}

class _Grid extends ConsumerWidget {
  final List<Media> items;
  const _Grid({required this.items});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (items.isEmpty) {
      return const EmptyState(
        icon: Icons.photo_library_outlined,
        title: 'No photos yet',
        subtitle: 'Tap the upload button to add your first photo.',
      );
    }

    return GridView.builder(
      // SliverGridDelegate packs thumbnails tightly, adapts to screen width
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: _columnCount(context),
        crossAxisSpacing: 2,
        mainAxisSpacing: 2,
      ),
      // Important: addAutomaticKeepAlives=false + addRepaintBoundaries=true
      // for smooth scroll performance with hundreds of thumbnails
      addAutomaticKeepAlives: false,
      itemCount: items.length + 1, // +1 for load-more sentinel
      itemBuilder: (context, index) {
        if (index == items.length) {
          // Trigger pagination when last item is visible
          ref.read(mediaListNotifierProvider.notifier).loadMore();
          return const SizedBox(height: 60, child: Center(child: CircularProgressIndicator()));
        }
        return _ThumbnailTile(media: items[index]);
      },
    );
  }

  int _columnCount(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    if (w >= 1024) return 6; // desktop / tablet landscape
    if (w >= 600)  return 4; // tablet portrait
    return 3;                // phone
  }
}

class _ThumbnailTile extends StatelessWidget {
  final Media media;
  const _ThumbnailTile({required this.media});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.go('/media/${media.id}'),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // CachedNetworkImage uses disk + memory LRU cache
          CachedNetworkImage(
            imageUrl: media.thumbUrls.small,
            fit: BoxFit.cover,
            placeholder: (_, __) => Container(color: Colors.grey[200]),
            errorWidget:  (_, __, ___) => const Icon(Icons.broken_image),
            // fadeIn for smooth appearance
            fadeInDuration: const Duration(milliseconds: 150),
          ),
          // Video indicator overlay
          if (media.isVideo)
            const Positioned(
              bottom: 4, right: 4,
              child: Icon(Icons.play_circle_fill, color: Colors.white, size: 20),
            ),
        ],
      ),
    );
  }
}
```

---

## 8. Media Detail Screen

```dart
// features/media/ui/media_detail_screen.dart
class MediaDetailScreen extends ConsumerWidget {
  final String mediaId;
  const MediaDetailScreen({super.key, required this.mediaId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mediaAsync = ref.watch(singleMediaProvider(mediaId));

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            icon: const Icon(Icons.download_outlined, color: Colors.white),
            onPressed: () => _download(context, ref),
          ),
          IconButton(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onPressed: () => _showOptions(context, ref),
          ),
        ],
      ),
      body: mediaAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error:   (e, _) => ErrorRetry(onRetry: () => ref.invalidate(singleMediaProvider(mediaId))),
        data:    (media) => media.isVideo
            ? VideoPlayerScreen(media: media)
            : _PhotoViewer(media: media),
      ),
    );
  }

  Future<void> _download(BuildContext context, WidgetRef ref) async {
    // 1. Get presigned URL from API
    // 2. Use dio to download to local temp file
    // 3. Use photo_manager to save to camera roll (Android/iOS)
    //    or trigger browser download (web)
  }
}

class _PhotoViewer extends StatelessWidget {
  final Media media;
  const _PhotoViewer({required this.media});

  @override
  Widget build(BuildContext context) {
    // PhotoView provides pinch-to-zoom. Use large thumbnail (1920px) for display.
    // The full original is only downloaded when explicitly requested.
    return PhotoView(
      imageProvider: CachedNetworkImageProvider(media.thumbUrls.large),
      minScale: PhotoViewComputedScale.contained,
      maxScale: PhotoViewComputedScale.covered * 4.0,
      heroAttributes: PhotoViewHeroAttributes(tag: media.id),
    );
  }
}
```

---

## 9. Auto-Backup (Background Sync)

Auto-backup uploads new camera roll photos/videos when the app is in the background.

```dart
// Configured on app startup
class AutoBackupService {
  static const String taskName = 'mycloud_auto_backup';

  static Future<void> register() async {
    await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
    await Workmanager().registerPeriodicTask(
      taskName,
      taskName,
      frequency: const Duration(hours: 1),
      constraints: Constraints(
        networkType: NetworkType.connected,
        requiresBatteryNotLow: true, // don't drain battery
      ),
    );
  }
}

// Top-level function required by Workmanager
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    if (taskName != AutoBackupService.taskName) return true;

    // Check which photos/videos are new since last backup
    final lastBackup = await _getLastBackupDate();
    final assets = await PhotoManager.getAssetPathList(type: RequestType.common);
    // ... upload each new asset using UploadManager
    // ... update lastBackup timestamp on success

    return true;
  });
}
```

---

## 10. Offline Handling

The app uses `connectivity_plus` to detect network state and handles offline gracefully:

```dart
// In providers, watch connectivity
@riverpod
Stream<ConnectivityResult> connectivity(ConnectivityRef ref) {
  return Connectivity().onConnectivityChanged;
}

// In the upload provider
@riverpod
class UploadQueue extends _$UploadQueue {
  @override
  List<PendingUpload> build() => [];

  Future<void> add(XFile file) async {
    final connectivity = ref.read(connectivityProvider).valueOrNull;
    if (connectivity == ConnectivityResult.none) {
      // Queue for later, persist to local storage
      _enqueueOffline(file);
      return;
    }
    await _uploadNow(file);
  }
}
```

Thumbnails are served from `CachedNetworkImage`'s disk cache when offline.

---

## 11. Theme

```dart
// core/theme/app_theme.dart
class AppTheme {
  static ThemeData light() {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF1565C0), // deep blue
        brightness: Brightness.light,
      ),
      appBarTheme: const AppBarTheme(
        elevation: 0,
        centerTitle: false,
      ),
      // Consistent card appearance
      cardTheme: CardTheme(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  static ThemeData dark() {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF1565C0),
        brightness: Brightness.dark,
      ),
      appBarTheme: const AppBarTheme(elevation: 0, centerTitle: false),
      cardTheme: CardTheme(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
```

---

## 12. Platform Build Notes

### Android (Android Studio)
- `minSdkVersion 21` (Android 5.0+)
- Add `READ_MEDIA_IMAGES`, `READ_MEDIA_VIDEO`, `INTERNET`, `FOREGROUND_SERVICE` permissions to `AndroidManifest.xml`
- Configure `WorkManager` for background backup
- `flutter_secure_storage` uses Android Keystore

### iOS (Xcode)
- Minimum iOS 13.0
- Add `NSPhotoLibraryUsageDescription` and `NSPhotoLibraryAddUsageDescription` to `Info.plist`
- `flutter_secure_storage` uses iOS Keychain
- Background fetch requires `Background Modes` → `Background fetch` capability

### Web (PWA)
- Auth tokens are stored only in `httpOnly` cookies; `flutter_secure_storage` is not used for web auth
- API requests must use cookies (`withCredentials = true`)
- MinIO CORS must allow the app origin for presigned `PUT` / `GET` / `HEAD`
- Add `manifest.json` for installable PWA
- Configure `CORS` in Nginx for the web origin
