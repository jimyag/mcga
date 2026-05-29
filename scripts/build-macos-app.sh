#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-release}"
APP_DIR="$ROOT/.build/MCGA.app"
EXECUTABLE="$ROOT/.build/$CONFIGURATION/MCGA"

cd "$ROOT"
swift build -c "$CONFIGURATION" --product MCGA

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
cp "$ROOT/Packaging/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$EXECUTABLE" "$APP_DIR/Contents/MacOS/MCGA"

echo "$APP_DIR"
