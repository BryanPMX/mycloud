#!/bin/sh
set -eu
umask 077
: "${RESTORE_DATABASE_URL:?An isolated empty target database is required}"
[ "${RESTORE_CONFIRM:-}" = isolated-empty-target ] || { echo 'Explicit restore acknowledgement is required.' >&2; exit 1; }
archive=${1:?Pass a custom-format PostgreSQL backup archive}
[ -f "$archive.sha256" ] || { echo 'Backup checksum is missing.' >&2; exit 1; }
parent=$(CDPATH= cd -- "$(dirname -- "$archive")" && pwd)
(cd "$parent" && sha256sum -c "$(basename "$archive").sha256")
count=$(psql "$RESTORE_DATABASE_URL" -X -A -t -v ON_ERROR_STOP=1 -c "SELECT count(*) FROM information_schema.tables WHERE table_schema='public'")
[ "$count" = 0 ] || { echo 'Refusing to restore into a nonempty database.' >&2; exit 1; }
pg_restore --exit-on-error --single-transaction --no-owner --no-privileges --dbname="$RESTORE_DATABASE_URL" "$archive"
psql "$RESTORE_DATABASE_URL" -X -v ON_ERROR_STOP=1 -c 'SELECT (SELECT count(*) FROM users) AS users,(SELECT count(*) FROM media) AS media;'
ledger=$(psql "$RESTORE_DATABASE_URL" -X -A -t -v ON_ERROR_STOP=1 -c "SELECT to_regclass('public.schema_migrations') IS NOT NULL")
if [ "$ledger" = t ]; then
 psql "$RESTORE_DATABASE_URL" -X -v ON_ERROR_STOP=1 -c 'SELECT count(*) AS migrations FROM schema_migrations;'
else
 echo 'Legacy archive restored without a migration ledger. Keep application writers paused for the reviewed upgrade.'
fi
echo 'PostgreSQL restore completed in the isolated target.'
