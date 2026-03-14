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

BACKUP_ROOT="${BACKUP_ROOT:-./backups/minio}"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
backup_dir="${BACKUP_ROOT}/${timestamp}"
manifest_path="${backup_dir}/manifest.txt"

mkdir -p "$backup_dir"

endpoint="${MINIO_SCHEME}://${MINIO_ENDPOINT}"

echo "Configuring MinIO alias ${MINIO_ALIAS} (${endpoint})"
"$MC_BIN" alias set "$MINIO_ALIAS" "$endpoint" "$MINIO_ACCESS_KEY" "$MINIO_SECRET_KEY" >/dev/null

for bucket in \
  "$MINIO_UPLOADS_BUCKET" \
  "$MINIO_ORIGINALS_BUCKET" \
  "$MINIO_THUMBS_BUCKET" \
  "$MINIO_AVATARS_BUCKET"
do
  target_dir="${backup_dir}/${bucket}"
  mkdir -p "$target_dir"
  echo "Mirroring ${bucket} to ${target_dir}"
  "$MC_BIN" mirror "${MINIO_ALIAS}/${bucket}" "$target_dir" >/dev/null
done

cat > "$manifest_path" <<EOF
created_at=${timestamp}
endpoint=${endpoint}
uploads_bucket=${MINIO_UPLOADS_BUCKET}
originals_bucket=${MINIO_ORIGINALS_BUCKET}
thumbs_bucket=${MINIO_THUMBS_BUCKET}
avatars_bucket=${MINIO_AVATARS_BUCKET}
EOF

echo "Backup complete: ${backup_dir}"
