#!/usr/bin/env sh

set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
FLUTTER_SDK_DIR="${FLUTTER_SDK_DIR:-$ROOT_DIR/.vercel/flutter}"
FLUTTER_VERSION="${FLUTTER_VERSION:-3.35.4}"

if [ ! -x "$FLUTTER_SDK_DIR/bin/flutter" ]; then
  mkdir -p "$(dirname "$FLUTTER_SDK_DIR")"
  git clone --depth 1 --branch "$FLUTTER_VERSION" https://github.com/flutter/flutter.git "$FLUTTER_SDK_DIR"
fi

# Vercel may restore an SDK cached by an earlier deployment.
if [ "$(git -C "$FLUTTER_SDK_DIR" describe --tags --exact-match HEAD 2>/dev/null || true)" != "$FLUTTER_VERSION" ]; then
  git -C "$FLUTTER_SDK_DIR" fetch --depth 1 origin "refs/tags/$FLUTTER_VERSION"
  git -C "$FLUTTER_SDK_DIR" checkout --detach FETCH_HEAD
fi

export PATH="$FLUTTER_SDK_DIR/bin:$PATH"

cd "$ROOT_DIR/flutter_app"
flutter --suppress-analytics --no-version-check pub get --enforce-lockfile
