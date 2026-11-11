#!/bin/sh
# This runs on EVERY container start, including a Docker-daemon restart.
set -eu
: "${MYCLOUD_STORAGE_UUID:?Expected data filesystem UUID is required}"
marker=${MYCLOUD_VOLUME_MARKER:-/storage-identity}
[ -f "$marker" ] && [ "$(cat "$marker")" = "$MYCLOUD_STORAGE_UUID" ] || {
 echo 'MyCloud storage identity missing or mismatched; refusing MinIO startup.' >&2
 exit 1
}
[ -d /data ] && [ -w /data ] || { echo 'MyCloud data is unavailable or read-only.' >&2; exit 1; }
exec /usr/bin/docker-entrypoint.sh "$@"
