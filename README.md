# MyCloud

This repository now contains both the design set and the current implemented backend plus the first live Flutter integration slices for MyCloud.

Current deployment domain plan:
- `https://mynube.live` for the future Flutter web app
- `https://api.mynube.live` for the Go API
- `https://minio.mynube.live` for MinIO presigned upload/download traffic
- `https://console.mynube.live` for the MinIO console/admin surface

Current implemented slices:
- PostgreSQL schema for `users`, `media`, `albums`, `album_media`, `shares`, `comments`, `favorites`, `jobs`, and `audit_log`
- JWT access/refresh auth with Redis-backed refresh session rotation and invite acceptance
- MinIO wiring for direct multipart uploads
- split internal/public MinIO endpoint support so server-side object operations stay on the Docker network while presigned URLs can target the public object host
- Redis-backed `process_media` and scheduled `cleanup` jobs, with worker-side scan, thumbnail generation, metadata extraction, and promotion flow
- self-service profile writes via `PATCH /api/v1/users/me` and avatar uploads via `PUT /api/v1/users/me/avatar`
- fixed-window API rate limiting plus response security headers in the Go middleware stack
- configurable API CORS handling for `mynube.live`-style web clients via `ALLOWED_ORIGINS`
- Redis-backed worker progress events plus authenticated `GET /ws/progress`
- SMTP-backed admin invite delivery when SMTP is configured, while still returning `invite_url` in the response
- admin user list/invite/update/deactivate endpoints and admin system stats
- album list/create/detail/update/delete, album-media add/remove, and album share management
- comment persistence plus media comment list/create/delete endpoints
- media favorites on `GET /media` and `GET /albums/:id/media`, plus favorite/unfavorite endpoints
- `POST /api/v1/auth/login`
- `POST /api/v1/auth/refresh`
- `POST /api/v1/auth/logout`
- `POST /api/v1/auth/invite/accept`
- `GET /api/v1/users/me`
- `PATCH /api/v1/users/me`
- `PUT /api/v1/users/me/avatar`
- `GET /api/v1/media`
- `POST /api/v1/media/:id/favorite`
- `DELETE /api/v1/media/:id/favorite`
- `GET /api/v1/albums`
- `POST /api/v1/albums`
- `GET /api/v1/albums/:id`
- `PATCH /api/v1/albums/:id`
- `DELETE /api/v1/albums/:id`
- `GET /api/v1/albums/:id/media`
- `POST /api/v1/albums/:id/media`
- `DELETE /api/v1/albums/:id/media/:mediaId`
- `GET /api/v1/albums/:id/shares`
- `POST /api/v1/albums/:id/shares`
- `DELETE /api/v1/albums/:id/shares/:shareId`
- `GET /api/v1/media/:id/comments`
- `POST /api/v1/media/:id/comments`
- `DELETE /api/v1/media/:id/comments/:commentId`
- `GET /api/v1/admin/users`
- `POST /api/v1/admin/users/invite`
- `PATCH /api/v1/admin/users/:id`
- `DELETE /api/v1/admin/users/:id`
- `GET /api/v1/admin/stats`
- `POST /api/v1/media/upload/init`
- `POST /api/v1/media/upload/:id/part-url`
- `POST /api/v1/media/upload/:id/complete`
- `GET /health`
- Flutter `MaterialApp.router` shell with live auth/session restore, live media/albums/comments/admin-stats reads, presigned thumbnail resolution, demo fallback mode, and environment-aware endpoint config
- validated Flutter tooling pass with `flutter analyze` and `flutter test`
- validated backend tooling pass with `go test ./...`

Use the numbered design docs for architecture and implementation status:
- [00-README.md](/Users/bryanpmx/Documents/Projects/mycloud/00-README.md) for the document index and status summary
- [03-api-reference.md](/Users/bryanpmx/Documents/Projects/mycloud/03-api-reference.md) for API status
- [04-database.md](/Users/bryanpmx/Documents/Projects/mycloud/04-database.md) for schema status
- [06-auth-security.md](/Users/bryanpmx/Documents/Projects/mycloud/06-auth-security.md) for auth/security status
- [09-subsystems-file-architecture.md](/Users/bryanpmx/Documents/Projects/mycloud/09-subsystems-file-architecture.md) for implementation order and current subsystem state
