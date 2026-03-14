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
| 07 | `07-flutter-client.md` | Flutter app structure, Riverpod, routing, upload, offline |
| 08 | `08-infrastructure.md` | Docker Compose, Nginx, monitoring, backup, scaling |
| 09 | `09-subsystems-file-architecture.md` | Starter subsystem decomposition and essential implementation file architecture |

---

## Project Summary

MyCloud is a **private, high-quality media cloud** for up to 50+ family members, self-hosted on an Ubuntu server. Users can upload, browse, download, and share photos and videos at original quality, from any device.

## Current Implementation Status

As of March 14, 2026, the repository includes the current working backend slices:

- runtime config loading from environment variables
- PostgreSQL, Redis, and MinIO wiring in the API composition root
- initial SQL migration with quota and album-count triggers
- secure JWT login, refresh, and logout flows
- authenticated `GET /users/me`
- authorization-aware `GET /media`, `GET /media/:id`, `GET /media/search`, and trash listing with cursor pagination
- presigned original download URLs via `GET /media/:id/url`
- media trash lifecycle: upload abort, soft delete, restore, permanent delete, and empty-trash flows
- album creation/listing/detail/update/delete, album-media membership, and album share management
- media comment read/write/delete flows backed by PostgreSQL soft deletes
- media favorite/unfavorite flows backed by PostgreSQL favorites
- direct multipart upload init, part-url presigning, and completion endpoints
- `process_media` job creation at upload completion
- search-vector and metadata index migration for media search/timeline reads
- worker-side staged upload scanning, promotion to originals, and media row finalization
- focused unit coverage for JWT, password hashing, cursor encoding, login orchestration, media upload commands, favorites, albums, and shares

Actual thumbnail file generation, WebSocket progress events, invite flow, the Flutter app, and infrastructure extras in the rest of the design docs are still planned work unless a section explicitly says otherwise. The thumbnail read endpoint is wired, but it returns `404` until real thumbnail objects exist in `fc-thumbs`.

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
