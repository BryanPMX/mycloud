#!/bin/sh
# Regression checks use only an isolated temp directory and injected test tools.
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM
mkdir "$work/bin" "$work/backups"
cat > "$work/bin/pg_dump" <<'SH'
#!/bin/sh
exit 42
SH
cat > "$work/bin/pg_restore" <<'SH'
#!/bin/sh
exit 0
SH
chmod +x "$work/bin/pg_dump" "$work/bin/pg_restore"
if PATH="$work/bin:$PATH" DATABASE_URL=validation-only BACKUP_ROOT="$work/backups" sh "$root/scripts/backup-postgres.sh" >/dev/null 2>&1; then
 echo 'Failed database dump was reported as successful' >&2; exit 1
fi
[ "$(find "$work/backups" -type f | wc -l | tr -d ' ')" = 0 ] || { echo 'Failed backup left success artifacts'; exit 1; }
if MYCLOUD_STORAGE_UUID=test MYCLOUD_VOLUME_MARKER="$work/missing" sh "$root/deploy/storage/minio-entrypoint.sh" >/dev/null 2>&1; then
 echo 'Missing SSD identity allowed MinIO to start' >&2; exit 1
fi
printf '%s\n' wrong-uuid > "$work/marker"
if MYCLOUD_STORAGE_UUID=test MYCLOUD_VOLUME_MARKER="$work/marker" sh "$root/deploy/storage/minio-entrypoint.sh" >/dev/null 2>&1; then
 echo 'Wrong SSD identity allowed MinIO to start' >&2; exit 1
fi
# Administrative bootstrap must never fall back to application credentials.
cat > "$work/bin/mc" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >> "$MC_CALLS"
SH
chmod +x "$work/bin/mc"
if MC_BIN="$work/bin/mc" MC_CALLS="$work/mc-calls" MINIO_ENDPOINT=validation.invalid MINIO_ALIAS=mycloud MINIO_SCHEME=http \
 MINIO_ROOT_USER= MINIO_ROOT_PASSWORD= \
 MINIO_ACCESS_KEY=validation-app MINIO_SECRET_KEY=validation-app-only \
 sh "$root/scripts/init-minio.sh" >/dev/null 2>&1; then
 echo 'Administrative bootstrap accepted application-only credentials' >&2; exit 1
fi
[ ! -e "$work/mc-calls" ] || { echo 'Bootstrap contacted MinIO without root credentials'; exit 1; }
MC_BIN="$work/bin/mc" MC_CALLS="$work/mc-calls" MINIO_ENDPOINT=validation.invalid MINIO_ALIAS=mycloud MINIO_SCHEME=http \
 MINIO_ROOT_USER=validation-root MINIO_ROOT_PASSWORD=validation-root-only \
 MINIO_ACCESS_KEY=validation-app MINIO_SECRET_KEY=validation-app-only \
 sh "$root/scripts/init-minio.sh" >/dev/null
IFS= read -r first_call < "$work/mc-calls"
[ "$first_call" = 'alias set mycloud http://validation.invalid validation-root validation-root-only' ] || {
 echo 'Administrative bootstrap did not use the explicit root identity' >&2; exit 1;
}
echo 'Backup failure, storage identity and administrative bootstrap checks passed.'
