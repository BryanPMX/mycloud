#!/usr/bin/env sh
# One connection holds the advisory lock through every transactional migration.
set -eu
: "${DATABASE_URL:?DATABASE_URL is required}"
[ "${1:-up}" = up ] || { echo 'Automatic rollback is disabled. Restore a verified backup or review one explicit down migration.' >&2; exit 1; }
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
migrations_dir=${MIGRATIONS_DIR:-${script_dir}/../migrations}
sql_file=$(mktemp)
trap 'rm -f "$sql_file"' EXIT HUP INT TERM
cat > "$sql_file" <<'SQL'
\set ON_ERROR_STOP on
SELECT pg_advisory_lock(684306102);
CREATE TABLE IF NOT EXISTS schema_migrations (
 version text PRIMARY KEY,
 checksum text NOT NULL,
 applied_at timestamptz NOT NULL DEFAULT now()
);
SQL
for migration in "$migrations_dir"/*.up.sql; do
 [ -f "$migration" ] || { echo 'No migrations found' >&2; exit 1; }
 version=$(basename "$migration" .up.sql)
 case "$version" in *[!a-zA-Z0-9_]*) echo 'Unsafe migration filename' >&2; exit 1;; esac
 if command -v sha256sum >/dev/null 2>&1; then
  checksum=$(sha256sum "$migration" | cut -d ' ' -f 1)
 else
  checksum=$(shasum -a 256 "$migration" | cut -d ' ' -f 1)
 fi
 cat >> "$sql_file" <<SQL
SELECT EXISTS(SELECT 1 FROM schema_migrations WHERE version = '$version') AS applied,
 NOT EXISTS(SELECT 1 FROM schema_migrations WHERE version = '$version' AND checksum <> '$checksum') AS checksum_ok \gset
\if :checksum_ok
\else
 \echo 'Previously applied migration changed: $version'
 SELECT 1/0;
\endif
\if :applied
\else
 \echo 'Applying $version'
 BEGIN;
SQL
 cat "$migration" >> "$sql_file"
 cat >> "$sql_file" <<SQL

INSERT INTO schema_migrations(version, checksum) VALUES ('$version', '$checksum');
COMMIT;
\endif
SQL
done
printf '\nSELECT pg_advisory_unlock(684306102);\n' >> "$sql_file"
# Do not enable shell tracing: the connection URI contains credentials.
psql "$DATABASE_URL" -X -q -v ON_ERROR_STOP=1 -f "$sql_file"
