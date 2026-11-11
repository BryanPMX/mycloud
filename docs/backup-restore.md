# Backup and restore

## Current protection and release gate

The proposed 1-TB SSD is primary storage, not a backup. The owner has not yet supplied an independent backup disk/NAS/off-site destination. Until a second copy and actual production restore rehearsal succeed, **do not cancel paid cloud storage or delete the existing cloud library**. Local synthetic restore tests validate the procedure/software, not the safety of production family media.

Back up PostgreSQL metadata and all four MinIO buckets together. Redis is replaceable session/dispatch state and should not be restored as an authority; restored users log in again and durable jobs recover from PostgreSQL. Keep stack/environment/NPM configuration separately in a private encrypted administrative backup. Never commit it.

## Implementation

- `backup-postgres` writes a custom-format archive, checks its structure with `pg_restore --list`, adds SHA-256 and retains validated daily archives for 14 days. A failed `pg_dump` cannot be masked by a pipeline/compressor. Incomplete archives never receive a success marker.
- `media-backup create /absolute/root` streams each current object with SHA-256, size, MIME and user metadata into a private snapshot; verifies the snapshot before publishing `latest`; and reuses unchanged files through hard links where supported. The CLI retains snapshots for 14 days (`MEDIA_BACKUP_RETENTION_DAYS`). No source object is deleted. This captures current objects, including staging; historical primary versions are not all archived as separate versions.
- `media-backup verify /absolute/snapshot` detects missing/corrupt bytes or unsafe manifest paths. Checksums detect corruption; they cannot repair it without another copy.
- `media-backup restore /absolute/snapshot` verifies before writes, refuses nonempty/public destination buckets, restores content type/metadata and reads back restored bytes for checksum comparison. A bucket prefix supports an isolated rehearsal on the same MinIO instance. Use credentials that can write only to the rehearsal destination.
- Hard-linked snapshots are history on **one** backup device, not separate independent copies. Do not edit their files. A second disk protects against primary-device loss; an off-site encrypted copy additionally protects against host loss, theft or fire.

## Coordinated scheduled backup

`scripts/backup-all.sh` checks the mounted backup UUID, rejects the same filesystem as live MinIO, locks out concurrent backups, and stops **only** `mycloud-api-1` and `mycloud-worker-1`. It runs the reviewed immutable backup image on the existing private PostgreSQL network, captures DB and media while writes/cleanup are paused, and resumes those two containers on success or failure. PostgreSQL/MinIO remain running. This causes a maintenance interval; measure its duration with the actual library before enabling the nightly schedule. Incremental media snapshots avoid re-downloading unchanged originals, but full checksum verification can be I/O intensive.

Before installing the timer, the owner must verify that the target is physically independent (a different filesystem UUID alone does not prove a different disk), ensure capacity for current data plus retention, create private configuration, run one successful manual backup and perform the restore test below.

Install the example service/timer from `deploy/systemd`, adjust `/opt/mycloud` if needed, and populate `/etc/mycloud/backup-schedule.env` from the example. Keep `/etc/mycloud/backup-credentials.env` mode 0600 with only required DB/MinIO settings. The backup image is `ghcr.io/bryanpmx/mycloud-backup:sha-FULL_REVIEWED_COMMIT`. Use a read-only MinIO backup account with bucket-policy inspection permissions, not a public alias.

The timer is **03:15 America/Denver**, with up to ten minutes of jitter. Configure `NODE_EXPORTER_TEXTFILE_DIR` only for an existing textfile collector directory already mounted by Node Exporter. Successful coordinated backups atomically update `mycloud_backup_last_success_unixtime`; Alertmanager rules detect overdue/missing success. No second monitoring platform is installed. For a future NAS/off-site target, mount and verify the destination explicitly and adapt the UUID guard to a fixed remote source; do not disable mount checks.

## Restore rehearsal

1. Select a matched database archive and media snapshot taken in the same write-paused window. Verify both checksums. Record date, source release/migration version, object count/bytes and archive paths privately.
2. Provision a **new empty database** and **empty private destination buckets** under a rehearsal prefix or an isolated MinIO. Never target the running production database/buckets. Keep the primary and paid cloud copies unchanged.
3. Set `RESTORE_DATABASE_URL` to that isolated database and `RESTORE_CONFIRM=isolated-empty-target`. Run `restore-postgres ARCHIVE.dump` from the backup image, with archive and `.sha256` mounted read-only. The helper refuses a nonempty database and restores in a single transaction. Legacy archives without `schema_migrations` are accepted and identified explicitly; keep application writers paused while applying the reviewed upgrade. Current archives additionally report their migration count.
4. Configure the media CLI for the isolated target's endpoint/credentials, set `RESTORE_CONFIRM=isolated-empty-target` and, if reusing an instance, `RESTORE_BUCKET_PREFIX=rehearsal-`. Run `media-backup restore /snapshot`. It checks privacy/emptiness before writes and verifies every restored object's actual bytes.
5. Start a separate API against the restored database, rehearsal bucket names and separate Redis database/namespace. Keep it private and disable SMTP to avoid sending invitations. Verify login, private/outsider denial, existing photo/video originals, thumbnails, family feed, storage usage and test-asset deletion. Then test durable worker recovery if relevant.
6. Record the result in [validation.md](validation.md), including a real family sample chosen by its owner, and remove only explicitly named rehearsal resources after acceptance. Production backups, old MinIO volume and paid storage remain intact.

For local synthetic verification, use `tests/integration/compose.yml` and the explicit validation database/ports. `scripts/restore-postgres.sh` plus `internal/infrastructure/backup/media_integration_test.go` exercise structural/byte restoration. These tests contain generated fixtures and never use live credentials.

## Recovery objectives and retention

A nightly completed backup gives an approximate **24-hour RPO**, plus any time a failed/overdue backup remains unresolved. RTO depends on restoring the full library and must be measured, not promised. Alert on backup age and actual free disk/SMART health using the existing monitoring stack. Test recovery after schema/storage changes and periodically thereafter. Account deletion removes live data asynchronously; independent backups expire under the configured retention policy.
