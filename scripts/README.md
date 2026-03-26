# `scripts`

Operational helper scripts live here.

Current script status on March 26, 2026:
- `migrate.sh` applies or rolls back the SQL migration set with `psql`
- `init-minio.sh` configures a MinIO alias, ensures the four application buckets exist, and enables versioning on originals
- `backup-postgres.sh` writes a timestamped compressed SQL backup using `pg_dump`
- `backup-minio.sh` mirrors the MinIO buckets into a timestamped local backup directory with `mc`
- `deploy-web.sh` now builds a release Flutter web bundle with the Mynube production URLs by default and can optionally copy the generated assets into `WEB_DEPLOY_DIR`

Keep scripts idempotent, shellcheck-friendly, and narrowly scoped to one operational task each.
