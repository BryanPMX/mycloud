#!/usr/bin/env sh

set -eu

MC_BIN="${MC_BIN:-mc}"
MINIO_ALIAS="${MINIO_ALIAS:-mycloud}"
MINIO_SCHEME="${MINIO_SCHEME:-http}"
MINIO_UPLOADS_BUCKET="${MINIO_UPLOADS_BUCKET:-fc-uploads}"
MINIO_ORIGINALS_BUCKET="${MINIO_ORIGINALS_BUCKET:-fc-originals}"
MINIO_THUMBS_BUCKET="${MINIO_THUMBS_BUCKET:-fc-thumbs}"
MINIO_AVATARS_BUCKET="${MINIO_AVATARS_BUCKET:-fc-avatars}"

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "$1 is required" >&2
    exit 1
  fi
}

require_command "$MC_BIN"

if [ -z "${MINIO_ENDPOINT:-}" ]; then
  echo "MINIO_ENDPOINT is required" >&2
  exit 1
fi

MINIO_ACCESS_KEY="${MINIO_ACCESS_KEY:-${MINIO_ROOT_USER:-}}"
MINIO_SECRET_KEY="${MINIO_SECRET_KEY:-${MINIO_ROOT_PASSWORD:-}}"

if [ -z "$MINIO_ACCESS_KEY" ]; then
  echo "MINIO_ACCESS_KEY or MINIO_ROOT_USER is required" >&2
  exit 1
fi
if [ -z "$MINIO_SECRET_KEY" ]; then
  echo "MINIO_SECRET_KEY or MINIO_ROOT_PASSWORD is required" >&2
  exit 1
fi

endpoint="${MINIO_SCHEME}://${MINIO_ENDPOINT}"

echo "Configuring MinIO alias ${MINIO_ALIAS} (${endpoint})"
"$MC_BIN" alias set "$MINIO_ALIAS" "$endpoint" "$MINIO_ACCESS_KEY" "$MINIO_SECRET_KEY" >/dev/null

for bucket in \
  "$MINIO_UPLOADS_BUCKET" \
  "$MINIO_ORIGINALS_BUCKET" \
  "$MINIO_THUMBS_BUCKET" \
  "$MINIO_AVATARS_BUCKET"
do
  echo "Ensuring bucket ${bucket}"
  "$MC_BIN" mb --ignore-existing "${MINIO_ALIAS}/${bucket}" >/dev/null
done

echo "Enabling versioning on ${MINIO_ORIGINALS_BUCKET}"
"$MC_BIN" version enable "${MINIO_ALIAS}/${MINIO_ORIGINALS_BUCKET}" >/dev/null

echo "MinIO bootstrap complete"
