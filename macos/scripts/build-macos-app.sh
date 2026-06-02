#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-release}"
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:--}"
APP_DIR="$ROOT/.build/MCGA.app"
EXECUTABLE="$ROOT/.build/$CONFIGURATION/MCGA"

cd "$ROOT"
swift build -c "$CONFIGURATION" --product MCGA

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"
cp "$ROOT/Packaging/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
cp "$ROOT/Packaging/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$EXECUTABLE" "$APP_DIR/Contents/MacOS/MCGA"

# Use a stable Developer ID / Apple Development identity when available. Ad-hoc
# signing is fine for packaging, but macOS TCC may require re-authorizing
# Accessibility after each rebuild because the code hash changes.
codesign --force --deep --sign "$CODESIGN_IDENTITY" "$APP_DIR"

echo "$APP_DIR"
