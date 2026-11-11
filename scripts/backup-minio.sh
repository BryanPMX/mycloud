#!/bin/sh
set -eu
umask 077
: "${BACKUP_ROOT:?Use a verified independent media backup destination}"
: "${BACKUP_WRITES_PAUSED:?Set yes only after pausing API and worker writes}"
exec "${MEDIA_BACKUP_BIN:-media-backup}" create "$BACKUP_ROOT"
