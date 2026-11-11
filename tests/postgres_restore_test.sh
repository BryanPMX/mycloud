#!/bin/sh
# Original-schema upgrade and restore rehearsal in a fresh disposable PostgreSQL.
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/mycloud-postgres-restore.XXXXXX")
container="mycloud-postgres-restore-$(basename "$work" | tr '[:upper:]' '[:lower:]')"
cleanup() {
  docker rm -f "$container" >/dev/null 2>&1 || true
  rm -rf "$work"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP
docker run -d --rm --name "$container" --network none --memory 256m --cpus 0.5 \
  -e POSTGRES_USER=validation -e POSTGRES_PASSWORD=validation-only-local \
  -e POSTGRES_DB=mycloud_validation postgres:16-alpine >/dev/null
attempt=0
until docker exec "$container" pg_isready -U validation -d mycloud_validation >/dev/null 2>&1; do
  attempt=$((attempt + 1))
  [ "$attempt" -lt 45 ] || { echo 'Restore fixture database did not become ready.' >&2; exit 1; }
  sleep 1
done
docker cp "$root/migrations" "$container:/test-migrations"
docker cp "$root/scripts/restore-postgres.sh" "$container:/tmp/restore-postgres.sh"
docker cp "$root/scripts/migrate.sh" "$container:/tmp/migrate.sh"
docker exec "$container" sh -c '
  set -eu
  for migration in /test-migrations/00[1-5]_*.up.sql; do
    psql -X -q -v ON_ERROR_STOP=1 -U validation -d mycloud_validation -f "$migration"
  done
' > "$work/legacy-migrations.log" 2>&1
docker exec -i "$container" psql -X -q -v ON_ERROR_STOP=1 -U validation -d mycloud_validation <<'SQL'
INSERT INTO users(id,email,display_name,password_hash,role,quota_bytes)
VALUES('00000000-0000-4000-8000-000000000039','restore@validation.invalid','Restore fixture','not-a-login-hash','admin',21474836480);
SQL
archive() {
  docker exec "$container" sh -c '
    set -eu
    pg_dump -U validation -d mycloud_validation --format=custom --no-owner --no-privileges -f "/tmp/$1.dump"
    cd /tmp
    sha256sum "$1.dump" > "$1.dump.sha256"
  ' sh "$1"
}
restore() {
  docker exec -e RESTORE_DATABASE_URL="postgres://validation:validation-only-local@127.0.0.1:5432/$1?sslmode=disable" \
    -e RESTORE_CONFIRM=isolated-empty-target "$container" sh /tmp/restore-postgres.sh "/tmp/$2.dump"
}
check_identity() {
  result=$(docker exec "$container" psql -X -A -t -v ON_ERROR_STOP=1 -U validation -d "$1" -c "SELECT count(*)=1 AND bool_and(id='00000000-0000-4000-8000-000000000039'::uuid AND email='restore@validation.invalid' AND display_name='Restore fixture' AND password_hash='not-a-login-hash' AND role='admin' AND active AND quota_bytes=21474836480 AND storage_used=0) FROM users")
  [ "$result" = t ] || { echo 'Restored account identity, role, hash or quota differed.' >&2; exit 1; }
}
archive legacy
docker exec "$container" createdb -U validation legacy_restore_validation
restore legacy_restore_validation legacy > "$work/legacy-restore.log" 2>&1
grep -F 'Legacy archive restored without a migration ledger.' "$work/legacy-restore.log" >/dev/null
check_identity legacy_restore_validation
if restore legacy_restore_validation legacy > "$work/nonempty-restore.log" 2>&1; then
  echo 'Restore accepted a nonempty database.' >&2; exit 1
fi
grep -F 'Refusing to restore into a nonempty database.' "$work/nonempty-restore.log" >/dev/null
check_identity legacy_restore_validation
docker exec -e DATABASE_URL='postgres://validation:validation-only-local@127.0.0.1:5432/mycloud_validation?sslmode=disable' \
  -e MIGRATIONS_DIR=/test-migrations "$container" sh /tmp/migrate.sh > "$work/upgrade.log" 2>&1
check_identity mycloud_validation
archive current
docker exec "$container" createdb -U validation current_restore_validation
restore current_restore_validation current > "$work/current-restore.log" 2>&1
check_identity current_restore_validation
[ "$(docker exec "$container" psql -X -A -t -U validation -d current_restore_validation -c 'SELECT count(*) FROM schema_migrations')" = 12 ]
echo 'Legacy/current PostgreSQL restores, original-schema upgrade, preserved account data and nonempty-target refusal passed.'
