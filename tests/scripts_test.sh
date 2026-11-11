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
echo 'Backup failure and missing/mismatched storage guard checks passed.'
