# Operational scripts

Production procedures are documented in [deployment](../docs/deployment.md), [storage](../docs/storage.md) and [backup/restore](../docs/backup-restore.md). The owner runs server commands; these helpers do not connect over SSH.

| Script | Purpose and required boundary |
| --- | --- |
| `migrate.sh` | Apply checksummed, transactionally recorded SQL migrations under one advisory lock. Automatic down migrations are disabled. |
| `setup-accounts-server.sh` | Prepare the two explicitly named account roles on the inventoried server, using a hidden password prompt, fresh database rollback archive, paused API and private login verification. No account identity or password is embedded. |
| `server-inventory.sh` | Read disk, mount, container and memory inventory without container environments or credentials. |
| `storage-preflight.sh` | Refuse startup unless the expected filesystem UUID is mounted and its identity marker matches. |
| `init-minio.sh` | Configure the private application buckets; never grant anonymous access. |
| `backup-postgres.sh` | Create and structurally check a private custom-format PostgreSQL archive, checksum and retention record. |
| `backup-minio.sh` | Run the verified media snapshot CLI with hashing, metadata preservation and retention. No source deletion. |
| `backup-all.sh` | Capture paired database/media backups with only API/worker paused; requires a mounted, independently verified backup destination. |
| `restore-postgres.sh` | Restore a checked archive only into an explicitly acknowledged empty database. |
| `deploy-web.sh` | Build production Flutter web assets; optionally copy them to `WEB_DEPLOY_DIR`. |
| `vercel-install.sh`, `vercel-build.sh` | Install the pinned Flutter SDK, enforce the lockfile and build real production data mode or an isolated sample preview. |
| `render-brand.swift` | Generate native/web cloud icons from the shared vector geometry. |

Helpers inside the backup image also include `media-backup`, `reconcile-storage`, `bootstrap-admin` and `account-setup`. Bootstrap is for an empty installation only. Existing-account password resets require explicit account selection and paused API writers; they preserve role, quota and media.

Run `sh tests/scripts_test.sh` for backup-failure and marker rejection checks. With local Docker, `sh tests/storage_guard_test.sh` checks the real pinned MinIO image, missing bind sources and a changed identity after container restart, using only temporary paths and a uniquely named disposable container. `sh tests/postgres_restore_test.sh` upgrades the original schema and restores legacy/current synthetic archives in a fresh PostgreSQL container with no published ports or Docker network. These tests never target production storage.
