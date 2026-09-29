#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-release}"
# macOS ties the Accessibility grant to the signing identity, and an ad-hoc signature is a
# new identity on every build. See README "Code signing".
SELF_SIGNED_IDENTITY="MCGA Self Signed"
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:-}"
# Never empty: bash 3.2 rejects expanding an empty array under set -u.
CODESIGN_OPTIONS=(--force --deep)
APP_DIR="$ROOT/.build/MCGA.app"
EXECUTABLE="$ROOT/.build/$CONFIGURATION/MCGA"

if [[ -z "$CODESIGN_IDENTITY" ]]; then
  if security find-identity -p codesigning | grep -Fq "\"$SELF_SIGNED_IDENTITY\""; then
    CODESIGN_IDENTITY="$SELF_SIGNED_IDENTITY"
  else
    echo "warning: \"$SELF_SIGNED_IDENTITY\" not found, signing ad-hoc; Accessibility must be re-granted after every install" >&2
    CODESIGN_IDENTITY="-"
  fi
fi

cd "$ROOT"
swift build -c "$CONFIGURATION" --product MCGA

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"
cp "$ROOT/Packaging/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
cp "$ROOT/Packaging/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$EXECUTABLE" "$APP_DIR/Contents/MacOS/MCGA"

# Hardened runtime and a secure timestamp are notarization requirements.
if [[ "$CODESIGN_IDENTITY" == "Developer ID Application:"* ]]; then
  CODESIGN_OPTIONS+=(--options runtime --timestamp)
fi

codesign "${CODESIGN_OPTIONS[@]}" --sign "$CODESIGN_IDENTITY" "$APP_DIR"
codesign --verify --strict --verbose=2 "$APP_DIR"

echo "$APP_DIR"
