# `scripts`

Operational helper scripts live here.

Current script status on March 14, 2026:
- `migrate.sh` applies or rolls back the SQL migration set with `psql`
- `init-minio.sh` configures a MinIO alias, ensures the four application buckets exist, and enables versioning on originals
- `backup-postgres.sh` writes a timestamped compressed SQL backup using `pg_dump`
- `backup-minio.sh` mirrors the MinIO buckets into a timestamped local backup directory with `mc`
- `deploy-web.sh` is still a placeholder because the Flutter web deployment slice has not started

Keep scripts idempotent, shellcheck-friendly, and narrowly scoped to one operational task each.
