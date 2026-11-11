#!/bin/sh
# Real pinned MinIO, disposable paths and a uniquely named container only.
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/mycloud-storage-guard.XXXXXX")
container="mycloud-storage-guard-$(basename "$work" | tr '[:upper:]' '[:lower:]')"
image=ghcr.io/bryanpmx/minio:RELEASE.2025-09-07T16-13-09Z
identity=00000000-0000-4000-8000-000000000039
cleanup() {
  docker rm -f "$container" >/dev/null 2>&1 || true
  rm -rf "$work"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP
printf '%s\n' "$identity" > "$work/identity"
run_guard() {
  docker run "$@" --name "$container" --platform linux/amd64 \
    --user "$(id -u):$(id -g)" --memory 512m --cpus 0.5 \
    --cap-drop ALL --security-opt no-new-privileges:true \
    -e MINIO_ROOT_USER=validation -e MINIO_ROOT_PASSWORD=validation-only-local \
    -e MYCLOUD_STORAGE_UUID="$identity" \
    --mount "type=bind,src=$work/data,dst=/data" \
    --mount "type=bind,src=$work/identity,dst=/storage-identity,readonly" \
    --mount "type=bind,src=$root/deploy/storage/minio-entrypoint.sh,dst=/mycloud-storage-guard.sh,readonly" \
    --entrypoint /bin/sh "$image" /mycloud-storage-guard.sh server /data --console-address :9001
}

# Docker's --mount has the same refusal-to-create behavior as create_host_path:false.
if run_guard -d > "$work/missing-data.log" 2>&1; then
  echo 'A missing data directory allowed MinIO startup.' >&2; exit 1
fi
[ ! -e "$work/data" ] || { echo 'Docker created a fallback data path.' >&2; exit 1; }
docker rm -f "$container" >/dev/null 2>&1 || true
mkdir "$work/data"
run_guard -d >/dev/null
attempt=0
until docker exec "$container" curl -fsS --max-time 2 http://127.0.0.1:9000/minio/health/live >/dev/null 2>&1; do
  attempt=$((attempt + 1))
  [ "$attempt" -lt 45 ] && [ "$(docker inspect "$container" --format '{{.State.Running}}')" = true ] || {
    echo 'MinIO did not become healthy with valid storage.' >&2; exit 1
  }
  sleep 1
done

# The guard must run on restart, not just on Compose creation.
docker stop --time 5 "$container" >/dev/null
printf '%s\n' wrong-identity > "$work/identity"
docker start "$container" >/dev/null
attempt=0
while [ "$(docker inspect "$container" --format '{{.State.Running}}')" = true ]; do
  attempt=$((attempt + 1))
  [ "$attempt" -lt 15 ] || { echo 'A changed identity allowed MinIO to keep running.' >&2; exit 1; }
  sleep 1
done
[ "$(docker inspect "$container" --format '{{.State.ExitCode}}')" = 1 ]
docker logs "$container" 2>&1 | grep -F 'MyCloud storage identity missing or mismatched; refusing MinIO startup.' >/dev/null
docker rm "$container" >/dev/null
rm "$work/identity"
if run_guard -d > "$work/missing-identity.log" 2>&1; then
  echo 'A missing identity file allowed MinIO startup.' >&2; exit 1
fi
[ ! -e "$work/identity" ] || { echo 'Docker created a fallback identity path.' >&2; exit 1; }
echo 'Real MinIO accepted valid storage and refused missing data, missing identity and changed identity after restart.'
