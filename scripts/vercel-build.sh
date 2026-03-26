#!/usr/bin/env sh

set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
FLUTTER_SDK_DIR="${FLUTTER_SDK_DIR:-$ROOT_DIR/.vercel/flutter}"

if [ ! -x "$FLUTTER_SDK_DIR/bin/flutter" ]; then
  sh "$ROOT_DIR/scripts/vercel-install.sh"
fi

export PATH="$FLUTTER_SDK_DIR/bin:$PATH"

if [ -z "${APP_ENV:-}" ] && [ -n "${VERCEL_ENV:-}" ]; then
  APP_ENV="$VERCEL_ENV"
fi

if [ "${VERCEL_ENV:-}" = "preview" ] && [ -z "${USE_DEMO_DATA:-}" ]; then
  USE_DEMO_DATA=true
fi

export APP_ENV="${APP_ENV:-production}"
export USE_DEMO_DATA="${USE_DEMO_DATA:-false}"

cd "$ROOT_DIR/flutter_app"
flutter --suppress-analytics --no-version-check pub get

sh "$ROOT_DIR/scripts/deploy-web.sh"
