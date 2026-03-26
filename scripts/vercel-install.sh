#!/usr/bin/env sh

set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
FLUTTER_SDK_DIR="${FLUTTER_SDK_DIR:-$ROOT_DIR/.vercel/flutter}"
FLUTTER_CHANNEL="${FLUTTER_CHANNEL:-stable}"

if [ ! -x "$FLUTTER_SDK_DIR/bin/flutter" ]; then
  mkdir -p "$(dirname "$FLUTTER_SDK_DIR")"
  git clone --depth 1 --branch "$FLUTTER_CHANNEL" https://github.com/flutter/flutter.git "$FLUTTER_SDK_DIR"
fi

export PATH="$FLUTTER_SDK_DIR/bin:$PATH"

cd "$ROOT_DIR/flutter_app"
flutter --suppress-analytics --no-version-check pub get
