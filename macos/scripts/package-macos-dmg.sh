#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DMG_PATH="$ROOT/.build/MCGA.dmg"

if ! command -v create-dmg >/dev/null 2>&1; then
  echo "create-dmg is required. Install it with: brew install create-dmg" >&2
  exit 1
fi

cd "$ROOT"
bash scripts/build-macos-app.sh

rm -f "$DMG_PATH"
create-dmg \
  --volname "MCGA" \
  --window-pos 200 120 \
  --window-size 600 400 \
  --icon-size 100 \
  --icon "MCGA.app" 175 190 \
  --hide-extension "MCGA.app" \
  --app-drop-link 425 190 \
  "$DMG_PATH" \
  ".build/MCGA.app"

echo "$DMG_PATH"
