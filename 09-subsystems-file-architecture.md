# 09 — Starter Subsystems File Architecture

---

## 1. Purpose

This file defines the **starter repository structure** for MyCloud.

It is intentionally minimal:

- only the essential files needed to start each subsystem
- no deep expansion yet
- once a subsystem starts implementation, we add the next files inside that subsystem

The goal is to keep the first implementation pass clear and lightweight without losing the overall architecture.

## Current Status

As of March 14, 2026, the following starter work is now implemented for MyCloud:

- backend core domain models and repository contracts
- environment config, JWT/password helpers, and cursor pagination helpers
- PostgreSQL pool + repositories for users, visible media, albums, shares, and comments
- PostgreSQL favorites persistence plus favorite-aware media list reads
- PostgreSQL search-vector, metadata, invite-token, and timeline index migration
- Redis client + refresh session store
- Postgres comments repository plus media comment flows
- HTTP router, auth middleware, request IDs, and structured request logging
- auth endpoints plus `GET /users/me`, media list/detail/search/trash routes, presigned original reads, media favorite routes, album/share routes, and media comment routes
- album creation/listing/detail/update/delete, album-specific media listing, album-media membership changes, and share list/create/revoke flows
- direct multipart upload init/part-url/complete/abort flows with MinIO wiring
- trash restore/permanent-delete/empty-trash flows with best-effort MinIO asset cleanup
- `process_media` queueing plus worker-side staging, scanning, and promotion
- initial migrations and local API/Postgres/Redis/MinIO compose setup

Still intentionally pending:

- audit log persistence
- Flutter app runtime wiring

---

## 2. Starter Top-Level Structure

```text
mycloud/
├── 00-README.md
├── 01-architecture.md
├── 02-backend-go.md
├── 03-api-reference.md
├── 04-database.md
├── 05-storage-media.md
├── 06-auth-security.md
├── 07-flutter-client.md
├── 08-infrastructure.md
├── 09-subsystems-file-architecture.md
├── .env.example
├── .gitignore
├── Makefile
├── docker-compose.yml
├── Dockerfile.api
├── Dockerfile.worker
├── go.mod
├── go.sum
├── cmd/
├── internal/
├── pkg/
├── migrations/
├── flutter_app/
├── nginx/
├── monitoring/
└── scripts/
```

This is enough to start implementation without prematurely creating every future folder.

---

## 3. Backend Starter Files

These are the essential files to begin implementing the Go backend and worker.

```text
cmd/
├── server/
│   └── main.go
└── worker/
    └── main.go

internal/
├── domain/
│   ├── user.go
│   ├── media.go
│   ├── album.go
│   ├── repositories.go
│   ├── services.go
│   └── errors.go
├── application/
│   ├── commands/
│   │   ├── init_upload.go
│   │   ├── complete_upload.go
│   │   └── create_album.go
│   └── queries/
│       ├── list_media.go
│       ├── get_media.go
│       └── list_albums.go
├── infrastructure/
│   ├── postgres/
│   │   ├── pool.go
│   │   ├── user_repository.go
│   │   ├── media_repository.go
│   │   └── album_repository.go
│   ├── minio/
│   │   ├── client.go
│   │   └── storage_service.go
│   ├── redis/
│   │   ├── client.go
│   │   ├── session_store.go
│   │   └── job_queue.go
│   ├── worker/
│   │   ├── registry.go
│   │   ├── image_processor.go
│   │   ├── video_processor.go
│   │   └── job_runner.go
│   └── clamav/
│       └── scanner.go
├── delivery/
│   ├── http/
│   │   ├── router.go
│   │   ├── errors.go
│   │   ├── middleware/
│   │   │   ├── auth.go
│   │   │   ├── request_id.go
│   │   │   └── logger.go
│   │   └── handlers/
│   │       ├── auth_handler.go
│   │       ├── media_handler.go
│   │       ├── album_handler.go
│   │       └── user_handler.go
│   └── ws/
│       └── progress_hub.go

pkg/
├── auth/
│   ├── jwt.go
│   └── password.go
├── config/
│   └── config.go
├── mime/
│   └── validator.go
└── pagination/
    └── cursor.go
```

### Why this is enough

- `domain/` is enough to define the core business model.
- `application/` is enough to start media upload and album flows.
- `infrastructure/` covers the minimum external dependencies.
- `delivery/` gives us an HTTP API and upload-progress WebSocket entry point.
- `pkg/` keeps auth, config, MIME validation, and cursor logic out of the main app layers.

Files for trash, admin, metrics, audit logs, and email can be added when those subsystems begin implementation.

---

## 4. Database Starter Files

The database subsystem can start with just the first migration and expand from there.

```text
migrations/
├── 001_initial_schema.up.sql
└── 001_initial_schema.down.sql
```

`001_initial_schema` should include the essential first tables:

- `users`
- `media`
- `albums`
- `album_media`
- `shares`
- `jobs`

Audit logs and admin-specific tables can be added in later migrations.

---

## 5. Storage and Media Pipeline Starter Files

These are the minimum files needed to begin the upload and processing pipeline.

```text
internal/infrastructure/minio/
├── client.go
└── storage_service.go

internal/infrastructure/worker/
├── registry.go
├── image_processor.go
├── video_processor.go
└── job_runner.go

internal/infrastructure/clamav/
└── scanner.go
```

This gives us:

- direct multipart upload support
- object read/write/presign support
- worker dispatch by MIME type
- image and video processing entry points
- virus scanning before promotion to permanent storage

Thumbnail helpers, cleanup processors, key builders, and reconciliation tools can be added later.

---

## 6. Flutter Starter Files

These are the minimum client files needed to start the app and connect it to the backend.

```text
flutter_app/
├── pubspec.yaml
├── analysis_options.yaml
├── lib/
│   ├── main.dart
│   ├── app.dart
│   ├── core/
│   │   ├── config/
│   │   │   └── app_config.dart
│   │   ├── network/
│   │   │   ├── api_client.dart
│   │   │   └── auth_interceptor.dart
│   │   ├── storage/
│   │   │   └── secure_storage.dart
│   │   ├── router/
│   │   │   └── app_router.dart
│   │   └── theme/
│   │       └── app_theme.dart
│   ├── features/
│   │   ├── auth/
│   │   │   ├── data/
│   │   │   │   └── auth_repository.dart
│   │   │   ├── providers/
│   │   │   │   └── auth_provider.dart
│   │   │   └── ui/
│   │   │       └── login_screen.dart
│   │   ├── media/
│   │   │   ├── data/
│   │   │   │   ├── media_repository.dart
│   │   │   │   └── upload_manager.dart
│   │   │   ├── providers/
│   │   │   │   └── media_list_provider.dart
│   │   │   └── ui/
│   │   │       ├── photo_grid_screen.dart
│   │   │       └── media_detail_screen.dart
│   │   └── albums/
│   │       ├── data/
│   │       │   └── album_repository.dart
│   │       ├── providers/
│   │       │   └── album_provider.dart
│   │       └── ui/
│   │           └── album_list_screen.dart
│   └── shared/
│       └── widgets/
│           ├── main_scaffold.dart
│           ├── thumbnail_image.dart
│           └── error_retry.dart
└── test/
```

### Why this is enough

- auth can be implemented end-to-end
- media listing and detail can be implemented end-to-end
- direct upload can be implemented early
- albums have enough structure to start without building every screen first

Comments, admin, trash, offline queueing, auto-backup, and WebSocket progress handling can be added once those subsystems start.

---

## 7. Infrastructure Starter Files

These are the minimum files needed to run the first implementation locally or on a small server.

```text
docker-compose.yml
Dockerfile.api
Dockerfile.worker
.env.example

nginx/
├── nginx.conf
└── conf.d/
    └── mycloud.conf

monitoring/
└── prometheus.yml

scripts/
├── migrate.sh
└── init-minio.sh
```

This is enough to start:

- reverse proxy
- API
- worker
- PostgreSQL
- Redis
- MinIO
- ClamAV
- basic metrics scraping

Backups, Grafana dashboards, exporters, alerts, and deployment automation can be added later.

---

## 8. Recommended Implementation Order

To keep the project manageable, the starter subsystems should be implemented in this order:

1. Backend core: domain, config, auth, database connection, router
2. Database: initial migration and first repositories
3. Media upload path: MinIO storage service, init upload, complete upload
4. Worker: queue consumption, scan, basic image/video processing
5. Flutter client: auth, media list, media detail, upload
6. Albums: backend and client basic CRUD
7. Infrastructure extras: monitoring, backup, cleanup, admin, secondary features

---

## 9. Final Rule

For now, each subsystem should start with the files above only.

When implementation of a subsystem begins:

- add new files inside that subsystem only
- avoid generating the full future tree up front
- let the codebase grow from real implementation needs

That keeps the architecture clean without turning the repo into empty scaffolding.
