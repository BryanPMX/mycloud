#!/usr/bin/env sh

set -eu

if [ -z "${DATABASE_URL:-}" ]; then
  echo "DATABASE_URL is required"
  exit 1
fi

direction="${1:-up}"

case "$direction" in
  up)
    find ./migrations -name '*.up.sql' | sort | while read -r file; do
      echo "Applying $file"
      psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f "$file"
    done
    ;;
  down)
    find ./migrations -name '*.down.sql' | sort -r | while read -r file; do
      echo "Rolling back $file"
      psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f "$file"
    done
    ;;
  *)
    echo "Usage: $0 [up|down]"
    exit 1
    ;;
esac
