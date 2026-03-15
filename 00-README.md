# MyCloud — Full System Design

> A private, self-hosted photo and video platform for families.
> Built with Flutter · Go · PostgreSQL · MinIO · Redis · Docker.

---

## Document Index

| # | File | Contents |
|---|------|----------|
| 00 | `00-README.md` | This file — project overview and index |
| 01 | `01-architecture.md` | System architecture, design patterns, SOLID principles |
| 02 | `02-backend-go.md` | Go project structure, Clean Architecture, all layers |
| 03 | `03-api-reference.md` | Full REST API — every endpoint, request/response shapes |
| 04 | `04-database.md` | PostgreSQL schema, indexes, migrations, query patterns |
| 05 | `05-storage-media.md` | MinIO layout, upload flow, FFmpeg/libvips processing pipeline |
| 06 | `06-auth-security.md` | JWT strategy, refresh tokens, authorization, security hardening |
| 07 | `07-flutter-client.md` | Current Flutter foundation shell plus the longer-term client architecture plan |
| 08 | `08-infrastructure.md` | Docker Compose, Nginx, monitoring, backup, scaling |
| 09 | `09-subsystems-file-architecture.md` | Starter subsystem decomposition and essential implementation file architecture |

---

## Project Summary

MyCloud is a **private, high-quality media cloud** for up to 50+ family members, self-hosted on an Ubuntu server. Users can upload, browse, download, and share photos and videos at original quality, from any device.

## Current Implementation Status

As of March 15, 2026, the repository includes the current working backend and Flutter integration slices:

- runtime config loading from environment variables
- PostgreSQL, Redis, and MinIO wiring in the API composition root
- initial SQL migration with quota and album-count triggers
- secure JWT login, refresh, logout, and invite-accept flows
- authenticated `GET /users/me` plus self-service `PATCH /users/me` and `PUT /users/me/avatar`
- response security headers and fixed-window rate limiting in the Go HTTP stack
- authorization-aware `GET /media`, `GET /media/:id`, `GET /media/search`, and trash listing with cursor pagination
- presigned original download URLs via `GET /media/:id/url`
- media trash lifecycle: upload abort, soft delete, restore, permanent delete, and empty-trash flows
- album creation/listing/detail/update/delete, album-media membership, and album share management
- media comment read/write/delete flows backed by PostgreSQL soft deletes
- media favorite/unfavorite flows backed by PostgreSQL favorites
- admin user list/invite/update/deactivate routes plus admin system stats
- append-only `audit_log` persistence for invite/admin actions via `005_audit_log`
- direct multipart upload init, part-url presigning, and completion endpoints
- `process_media` job creation at upload completion
- scheduled `cleanup` job enqueueing for trash-purge and expired-share maintenance
- Redis pub/sub-backed worker progress events plus authenticated `GET /ws/progress`
- search-vector and metadata index migration for media search/timeline reads
- worker-side staged upload scanning, promotion to originals, real WebP thumbnail generation, richer metadata extraction, and media row finalization
- SMTP invite delivery when SMTP transport is configured, with Mailpit-friendly local defaults in `.env.example`
- focused unit coverage for JWT, password hashing, cursor encoding, login orchestration, invite acceptance, admin mutations, media upload commands, favorites, albums, and shares
- Flutter `MaterialApp.router` shell with SDK-only routing, adaptive `NavigationBar`/`NavigationRail` layout, live auth restore, live media/albums/comments/admin-stats reads, browser multipart upload orchestration, `/ws/progress` reconciliation, and environment-backed endpoint config
- Flutter smoke coverage for boot, demo sign-in, and route navigation plus DTO parsing coverage for API and worker progress payloads in `flutter_app/test/core/`

The Flutter client now has validated live reads plus the browser upload/progress path. The biggest remaining client work is the remaining write flows, secure native token persistence, richer admin screens, and the longer-term mobile/offline slices unless a section explicitly says otherwise.

### Design Goals

- **Original quality preserved** — no re-encoding of originals, lossless storage.
- **Cross-platform** — single Flutter codebase targets Web, Android, and iOS.
- **Secure** — end-to-end HTTPS, JWT auth, per-resource authorization, ClamAV scanning.
- **Maintainable** — Clean Architecture + SOLID throughout; every layer independently testable.
- **Self-hosted** — runs entirely on your Ubuntu server; no third-party cloud dependency.
- **Family-scale** — designed comfortably for 50 users; straightforward to scale further.

---

## Technology Choices

### Why Flutter
- Single codebase for Web (PWA), Android (Android Studio), and iOS (Xcode).
- You already know Dart/Flutter — no retraining cost.
- Excellent packages for chunked upload, image caching, video playback, and camera roll access.
- Hot reload dramatically speeds up UI iteration.

### Why Go (backend)
- Compiles to a single binary — trivial to deploy and containerize.
- Excellent concurrency model for parallel upload handling and media processing.
- Low memory footprint (~80 MB at rest) — important when sharing 16 GB with other services.
- Strong standard library for HTTP, JSON, crypto. Gin adds routing, middleware, and request binding.

### Why MinIO
- S3-compatible object storage, self-hosted on your Ubuntu server.
- Handles arbitrarily large files (photos, 4K videos) natively.
- Generates presigned URLs — clients upload and download media directly without the API proxying the bytes.
- Transparently expands when you add disk space.
- No egress fees, no cloud dependency.

### Why PostgreSQL
- Relational model fits the data perfectly (users → albums → media → shares → comments).
- JSONB for flexible media metadata (EXIF data, video codec info).
- Full-text search built in.
- Mature, battle-tested, excellent tooling.

### Why Redis
- Refresh token store with per-token revocation (JWT access tokens are stateless; refresh tokens need state).
- Upload session tracking (chunked upload resumption).
- Best-effort job queue (background media processing via simple LPUSH/BRPOP).
- Optional short-lived cache for expensive aggregation queries.

---

## High-Level Architecture

```
[Flutter Web]  [Flutter Android]  [Flutter iOS]  [Flutter Admin]
       |               |                |                |
       └───────────────┴────────────────┴────────────────┘
                                │
                    ┌───────────▼───────────┐
                    │  Nginx (TLS + proxy)  │
                    └───────────┬───────────┘
               ┌────────────────┼────────────────┐
               ▼                ▼                ▼
         [Go REST API]                     [Media Worker]
               │                                 │
    ┌──────────┼─────────────────────────────────┼──────────┐
    ▼          ▼                                 ▼          ▼
[Postgres]  [Redis]                           [MinIO]  [ClamAV]
```

Authentication lives inside the main Go API binary in `pkg/auth` and the HTTP auth handlers. The separation in earlier diagrams was conceptual only; the deployment model is a single API service plus a separate media worker.

---

## Server Resources

| Component | RAM (at rest) | Disk |
|-----------|--------------|------|
| Go API | ~80 MB | — |
| Go Media Worker | ~512 MB peak | — |
| PostgreSQL | ~512 MB | ~2 GB (metadata) |
| Redis | ~100 MB | — |
| MinIO | ~256 MB | Up to full 1 TB |
| Nginx | ~50 MB | — |
| Prometheus + Grafana | ~400 MB | ~5 GB (metrics) |
| ClamAV | ~512 MB | ~1 GB (definitions) |
| **Total estimate** | **~2.4 GB** | **~8 GB + media** |

With 16 GB RAM and 1 TB storage, you have significant headroom for your existing backends and for burst media encoding jobs.

---

## Conventions Used in This Document Set

- All Go package paths use the module prefix `github.com/yourorg/mycloud`.
- All SQL uses PostgreSQL 15+ syntax.
- All environment variable names use `SCREAMING_SNAKE_CASE`.
- API paths are versioned under `/api/v1/`.
- Times are UTC ISO 8601 (`2024-06-15T10:30:00Z`).
- Media IDs, User IDs, Album IDs, Share IDs are UUIDs (v4).
