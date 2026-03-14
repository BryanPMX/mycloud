#!/usr/bin/env sh

set -eu

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "$1 is required" >&2
    exit 1
  fi
}

require_command pg_dump
require_command gzip

if [ -z "${DATABASE_URL:-}" ]; then
  echo "DATABASE_URL is required" >&2
  exit 1
fi

BACKUP_ROOT="${BACKUP_ROOT:-./backups/postgres}"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
archive_path="${BACKUP_ROOT}/mycloud-postgres-${timestamp}.sql.gz"
tmp_path="${archive_path}.partial"

mkdir -p "$BACKUP_ROOT"

cleanup() {
  rm -f "$tmp_path"
}

trap cleanup EXIT HUP INT TERM

echo "Creating PostgreSQL backup at ${archive_path}"
pg_dump --no-owner --no-privileges "$DATABASE_URL" | gzip -c > "$tmp_path"
mv "$tmp_path" "$archive_path"

trap - EXIT HUP INT TERM
echo "Backup complete: ${archive_path}"
