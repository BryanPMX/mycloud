#!/bin/sh
set -eu
: "${MYCLOUD_STORAGE_UUID:?Set the UUID of the prepared Linux data filesystem}"
MYCLOUD_DATA_MOUNT=${MYCLOUD_DATA_MOUNT:-/srv/mycloud-data}
mountpoint -q "$MYCLOUD_DATA_MOUNT" || { echo 'MyCloud data disk is not mounted; refusing storage startup.' >&2; exit 1; }
actual=$(findmnt -n -o UUID --target "$MYCLOUD_DATA_MOUNT")
[ "$actual" = "$MYCLOUD_STORAGE_UUID" ] || { echo 'MyCloud storage UUID mismatch.' >&2; exit 1; }
fstype=$(findmnt -n -o FSTYPE --target "$MYCLOUD_DATA_MOUNT")
case "$fstype" in ext4|xfs|btrfs) ;; *) echo 'MyCloud production storage requires a prepared Linux filesystem.' >&2; exit 1;; esac
[ -r "$MYCLOUD_DATA_MOUNT/.mycloud-volume" ] || { echo 'Storage identity marker is missing.' >&2; exit 1; }
[ "$(cat "$MYCLOUD_DATA_MOUNT/.mycloud-volume")" = "$MYCLOUD_STORAGE_UUID" ] || { echo 'Storage identity marker does not match.' >&2; exit 1; }
[ -d "$MYCLOUD_DATA_MOUNT/minio" ] || { echo 'MinIO data directory is missing.' >&2; exit 1; }
echo 'MyCloud storage preflight passed.'
