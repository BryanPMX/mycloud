#!/bin/sh
# Run via the provided timer only after configuring an INDEPENDENT backup target.
set -eu
umask 077
: "${MYCLOUD_BACKUP_MOUNT:?Independent mounted backup destination required}"
: "${MYCLOUD_BACKUP_UUID:?Backup filesystem UUID required}"
: "${MYCLOUD_BACKUP_ENV_FILE:?Private database and read-only object credentials env file required}"
: "${MYCLOUD_BACKUP_IMAGE:?Immutable mycloud-backup release image required}"
mountpoint -q "$MYCLOUD_BACKUP_MOUNT" || { echo 'Backup target is not mounted.' >&2; exit 1; }
[ "$(findmnt -n -o UUID --target "$MYCLOUD_BACKUP_MOUNT")" = "$MYCLOUD_BACKUP_UUID" ] || { echo 'Backup UUID mismatch.' >&2; exit 1; }
source=$(docker inspect mycloud-minio-1 --format '{{range .Mounts}}{{if eq .Destination "/data"}}{{.Source}}{{end}}{{end}}')
[ -n "$source" ] || exit 1
[ "$(findmnt -n -o UUID --target "$source")" != "$MYCLOUD_BACKUP_UUID" ] || { echo 'Media and backup share the same filesystem; use an independent target.' >&2; exit 1; }
network=$(docker inspect mycloud-postgres-1 --format '{{range $name,$config := .NetworkSettings.Networks}}{{$name}}{{println}}{{end}}')
# PostgreSQL is expected to be on exactly one private MyCloud network.
[ "$(printf '%s\n' "$network" | wc -l | tr -d ' ')" = 1 ] || { echo 'Review PostgreSQL backup network selection.' >&2; exit 1; }
exec 9>"$MYCLOUD_BACKUP_MOUNT/.mycloud-backup.lock"
flock -n 9 || { echo 'Another MyCloud backup is running.' >&2; exit 1; }
mkdir -p "$MYCLOUD_BACKUP_MOUNT/postgres" "$MYCLOUD_BACKUP_MOUNT/media"
resume() { docker start mycloud-api-1 mycloud-worker-1 >/dev/null; }
trap resume EXIT HUP INT TERM
docker stop --time 30 mycloud-api-1 mycloud-worker-1 >/dev/null
docker run --rm --network "$network" --env-file "$MYCLOUD_BACKUP_ENV_FILE" --mount "type=bind,src=$MYCLOUD_BACKUP_MOUNT,dst=/backup" -e BACKUP_ROOT=/backup/postgres "$MYCLOUD_BACKUP_IMAGE" backup-postgres
docker run --rm --network "$network" --env-file "$MYCLOUD_BACKUP_ENV_FILE" --mount "type=bind,src=$MYCLOUD_BACKUP_MOUNT,dst=/backup" -e BACKUP_ROOT=/backup/media -e BACKUP_WRITES_PAUSED=yes "$MYCLOUD_BACKUP_IMAGE" backup-minio
resume
trap - EXIT HUP INT TERM
if [ -n "${NODE_EXPORTER_TEXTFILE_DIR:-}" ]; then
 metric=$(mktemp "$NODE_EXPORTER_TEXTFILE_DIR/.mycloud-backup.XXXXXX")
 printf 'mycloud_backup_last_success_unixtime %s\n' "$(date +%s)" > "$metric"
 chmod 644 "$metric"
 mv "$metric" "$NODE_EXPORTER_TEXTFILE_DIR/mycloud_backup.prom"
fi
echo 'Coordinated database and media backup succeeded. Services resumed.'
