#!/bin/sh
set -eu
umask 077
: "${DATABASE_URL:?DATABASE_URL is required}"
: "${BACKUP_ROOT:?Use a verified, independent backup destination}"
command -v pg_dump >/dev/null
command -v pg_restore >/dev/null
mkdir -p "$BACKUP_ROOT"
timestamp=$(date -u +%Y%m%dT%H%M%SZ)
archive="$BACKUP_ROOT/mycloud-postgres-$timestamp.dump"
[ ! -e "$archive" ] || { echo 'Backup archive already exists.' >&2; exit 1; }
partial=$(mktemp "$BACKUP_ROOT/.postgres-partial.XXXXXX")
trap 'rm -f "$partial"' EXIT HUP INT TERM
# No pipeline: failure of pg_dump cannot be masked by a successful compressor.
pg_dump --no-owner --no-privileges --format=custom --file="$partial" "$DATABASE_URL"
pg_restore --list "$partial" >/dev/null
mv "$partial" "$archive"
if command -v sha256sum >/dev/null 2>&1; then
 (cd "$BACKUP_ROOT" && sha256sum "$(basename "$archive")") > "$archive.sha256"
else
 (cd "$BACKUP_ROOT" && shasum -a 256 "$(basename "$archive")") > "$archive.sha256"
fi
trap - EXIT HUP INT TERM
# Only validated archives receive checksums and qualify for retention cleanup.
retention=${POSTGRES_BACKUP_RETENTION_DAYS:-14}
case "$retention" in ''|*[!0-9]*) echo 'Invalid retention' >&2; exit 1;; esac
[ "$retention" -ge 1 ] || exit 1
find "$BACKUP_ROOT" -type f -name 'mycloud-postgres-*.dump' -mtime +"$retention" -exec sh -c 'for archive do [ -f "$archive.sha256" ] && rm -f "$archive" "$archive.sha256"; done' sh {} +
echo 'PostgreSQL backup created and archive structure verified. A restore rehearsal is still required.'
