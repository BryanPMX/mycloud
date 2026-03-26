#!/usr/bin/env sh

set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
APP_DIR="$ROOT_DIR/flutter_app"
OUTPUT_DIR="$APP_DIR/build/web"

: "${APP_NAME:=Mynube}"
: "${APP_BASE_URL:=https://mynube.live}"
: "${API_BASE_URL:=https://api.mynube.live/api/v1}"
: "${WS_BASE_URL:=wss://api.mynube.live/ws/progress}"
: "${APP_ENV:=production}"

cd "$APP_DIR"

flutter --suppress-analytics --no-version-check build web --release \
  --dart-define=APP_NAME="$APP_NAME" \
  --dart-define=APP_BASE_URL="$APP_BASE_URL" \
  --dart-define=API_BASE_URL="$API_BASE_URL" \
  --dart-define=WS_BASE_URL="$WS_BASE_URL" \
  --dart-define=APP_ENV="$APP_ENV" \
  "$@"

if [ -n "${WEB_DEPLOY_DIR:-}" ]; then
  mkdir -p "$WEB_DEPLOY_DIR"
  cp -R "$OUTPUT_DIR"/. "$WEB_DEPLOY_DIR"/
  echo "Copied release web assets to $WEB_DEPLOY_DIR"
else
  echo "Built release web assets at $OUTPUT_DIR"
  echo "Set WEB_DEPLOY_DIR=/path/to/docroot to copy the output after the build."
fi
