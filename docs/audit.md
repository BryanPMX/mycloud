# Production audit — 10 November 2026

## Scope and evidence

Inspected Go commands, domain interfaces, application commands/queries, HTTP middleware/handlers, PostgreSQL repositories and five existing migrations, Redis queues/sessions, MinIO storage, ClamAV, FFmpeg processing, Flutter repositories/providers/screens/tests/native scaffolds, Dockerfiles, all Compose stacks, workflows, scripts, monitoring configuration, and numbered design documents. The initial `go test ./...` passes. This is a source audit; running containers, deployed configuration, disk identity and backup copies have **not** been verified. The owner runs server commands. Local Docker is not running.

## Existing architecture and working source implementations

- Go/Gin API and separate serial Go worker; PostgreSQL metadata, private MinIO originals/uploads/thumbnails/avatars, Redis refresh sessions/upload sessions/job dispatch/progress.
- Flutter iOS/Android/web client, secure native credential storage, invitation acceptance, session restoration, gallery/search/favorites/trash, multipart photo/video picker uploads, progress reconciliation, albums, explicit album sharing, comments, profile/avatar and admin invitation/account screens.
- bcrypt passwords, signed access/refresh JWTs, hashed invitation tokens, expiring read URLs, owner/share queries, rate limits, security headers and CORS.
- Soft deletion retains quota for 30 days; database triggers account for media originals. Album removal and share revocation preserve originals.
- Production is `deploy/portainer-stack.npm.yml`, GHCR image builds and Portainer webhook. MinIO release is intentionally pinned; console publishes only on loopback. PostgreSQL/Redis have no production host ports.

## Critical findings at discovery

1. Upload quota is checked before upload without a reservation/row lock; concurrent uploads exceed quota. Completed object size/content is trusted from client metadata. Pending sessions exist only in Redis and abandoned multipart data has no verified lifecycle policy.
2. Administration can bypass ownership to delete/restore media and manage another owner's album/sharing. This conflicts with the requested owner-control policy.
3. Refresh validation and revocation are separate Redis operations, allowing concurrent replay. JWT method acceptance is wider than the intended HS256 algorithm. Proxy trust defaults allow forwarded-IP rate-limit spoofing.
4. Trash purge deletes database rows before MinIO deletion. Storage failure discards retry metadata and releases quota while orphaned objects remain.
5. Redis BRPOP permanently removes a job before processing; worker death or Redis loss strands queued/running database jobs. No retry recovery or claim protection. FFmpeg has no pipeline deadline, input byte cap, pixel cap or protocol restrictions.
6. Migrations are replayed wholesale without a version ledger, checksum verification, transaction or deployment lock. Development PostgreSQL init mounts both up and down scripts.
7. PostgreSQL backup uses a POSIX pipeline without pipefail: a failed dump can produce a successful empty backup. No retention policy, verified restore rehearsal or scheduled configuration. Media backups need a separate physical destination.
8. Health is liveness only. Metrics are a placeholder. CI jobs are placeholders, and image deployment does not depend on tests.
9. No Docker build context exclusions; local secrets, user files and build output can enter build context/layers. Runtime API/worker run as root. Local Compose publishes databases/console on all interfaces and uses unpinned MinIO latest.
10. SSD is not identified or inspected. Current production named volume must be retained until a verified migration. Simply switching the bind mount is unsafe.

## Product and technical debt

- “Family” currently means all active invited accounts in one installation; nil recipient UUID means entire installation. There are no isolated household tables, membership roles or household invitations. Never treat this as multi-tenant isolation.
- Albums implement selective sharing but are not authored chronological feed posts. No dedicated family feed or post/media model exists at discovery.
- No self-service account deletion or password change. Native video playback/background upload and App Store readiness need device validation; existing native scaffolds/build claims are not evidence of current production acceptance.
- Client contains implementation/status text in consumer flows and a large media screen. Keep Flutter; simplify copy and add focused features without a rewrite.
- Database repositories have no real-PostgreSQL boundary tests. Existing unit tests use fakes and cannot prove SQL authorization, trigger accounting or crash recovery.
- Numbered docs mix proposed and implemented architecture, include stale public console guidance, and machine-specific links. README needs operational truth and explicit release gates.

## Recommended architecture

Preserve Go, Flutter, PostgreSQL, Redis, ClamAV, MinIO, NPM and existing monitoring. PostgreSQL owns durable authorization, reservations, jobs and deletion retry state; Redis remains replaceable dispatch/session state. Originals stay private. Short-lived URLs follow database authorization. Account administrators administer accounts without implicit access to another owner's media. Add versioned migrations, bounded processing, recovery and tested backups before rollout. SSD adoption is opt-in after the owner's read-only inspection and verified second copy.

See [implementation-plan.md](implementation-plan.md) for ordering and acceptance gates. Findings above describe the baseline; validation and changes are recorded in [validation.md](validation.md).
