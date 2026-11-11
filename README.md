# Mynube

A private personal vault: individual accounts and quotas, private photo/video libraries, selective album sharing and chronological household feeds. Go API/worker, Flutter for iPhone/Android/web, PostgreSQL metadata, Redis sessions/dispatch and private MinIO media.

This branch implements product completion and production hardening. **Production deployment, guarded SSD migration, independent backup installation and family/device acceptance remain explicit release gates.** Local tests do not certify live data safety. Keep existing paid storage and cloud originals until production migration, independent backups and an actual production restore test succeed.

Start with [the audit](docs/audit.md), [implementation plan](docs/implementation-plan.md) and [validation record](docs/validation.md). Operational documentation:

- [Architecture and media lifecycle](docs/architecture.md)
- [Authorization, sessions and privacy](docs/security.md)
- [Account permissions, storage quotas and RAM/CPU limits](docs/permissions-and-limits.md)
- [Storage, quotas and SSD migration](docs/storage.md)
- [Backup and verified restore](docs/backup-restore.md)
- [Deployment, monitoring and iPhone acceptance](docs/deployment.md)
- [Disaster recovery](docs/disaster-recovery.md)

Public HTTPS hosts are `api.mynube.live` and `minio.mynube.live`; the Flutter web app uses `mynube.live`. The MinIO console and all administration stay on localhost/SSH/Tailscale. Never expose a console proxy or make buckets anonymous.

Production uses `deploy/portainer-stack.npm.yml`. The MinIO image remains **`ghcr.io/bryanpmx/minio:RELEASE.2025-09-07T16-13-09Z`**. The SSD and private monitoring overrides are optional, separately documented changes. Current production storage is retained as `mycloud_minio_data`; changing a mount is not a migration.

For local development, copy `.env.example` into a private `.env`, set actual development credentials/HTTPS choices, and run `docker compose up -d --build`. Its services bind to loopback and migrations run through a version ledger. A new empty installation can use the documented `bootstrap-admin` helper; existing deployments must never bootstrap/reset accounts.

Validation:

```sh
go test -race ./...
go vet ./...
sh tests/scripts_test.sh
cd flutter_app
flutter pub get --enforce-lockfile
flutter analyze
flutter test
flutter build web --release --dart-define=USE_DEMO_DATA=false
```

Real PostgreSQL/Redis/MinIO/ClamAV and complete upload/feed tests use the isolated `tests/integration/compose.yml` stack; see its README. CI gates publishing of API, worker, migration and backup images. Use one reviewed immutable `sha-FULL_COMMIT` tag for rollout and preserve rollback copies.

Native uploads are chunked and limited to 512 MiB per file. Keep the app open during transfer; OS-managed background backup/resume after termination and App Store submission are not yet accepted production capabilities. The existing numbered design documents remain historical references; `docs/` describes the current operational design.

The consumer client is branded **Mynube**, a private personal vault: a photographic library, collections and a deliberately small shared circle. See [the design system](docs/design-system.md) for branding, reusable components, responsive layouts and accessibility behavior. The Flutter implementation supports desktop web, iOS and Android without changing the existing API/storage architecture.
