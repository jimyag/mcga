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

# Ad-hoc sign the application bundle so macOS doesn't mark it as damaged
codesign --force --deep --sign - "$APP_DIR"

echo "$APP_DIR"
