#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-release}"
# macOS ties the Accessibility grant to the signing identity, and an ad-hoc signature is a
# new identity on every build. See README "Code signing".
SELF_SIGNED_IDENTITY="MCGA Self Signed"
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:-}"
# Never empty: bash 3.2 rejects expanding an empty array under set -u.
CODESIGN_OPTIONS=(--force)
APP_DIR="$ROOT/.build/MCGA.app"
SPARKLE_DIR="$APP_DIR/Contents/Frameworks/Sparkle.framework"

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
BIN_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path)"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"
mkdir -p "$APP_DIR/Contents/Frameworks"
cp "$ROOT/Packaging/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
cp "$ROOT/Packaging/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$BIN_DIR/MCGA" "$APP_DIR/Contents/MacOS/MCGA"
ditto "$BIN_DIR/Sparkle.framework" "$SPARKLE_DIR"
# The XPC services only serve sandboxed apps, and MCGA is not sandboxed.
rm -rf "$SPARKLE_DIR/XPCServices" "$SPARKLE_DIR/Versions/B/XPCServices"

# The version comes from the latest git tag (the release workflow checks out the tag it
# builds); without git or tags the bundle keeps the Info.plist values. Sparkle compares
# CFBundleVersion with the appcast, so both keys carry the tag version.
if VERSION="$(git -C "$ROOT" describe --tags --abbrev=0 2>/dev/null)"; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION#v}" "$APP_DIR/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${VERSION#v}" "$APP_DIR/Contents/Info.plist"
fi

# Hardened runtime and a secure timestamp are notarization requirements.
if [[ "$CODESIGN_IDENTITY" == "Developer ID Application:"* ]]; then
  CODESIGN_OPTIONS+=(--options runtime --timestamp)
fi

# Sign inside out; Sparkle's docs rule out --deep for its helpers.
for code in "$SPARKLE_DIR/Versions/B/Autoupdate" "$SPARKLE_DIR/Versions/B/Updater.app" "$SPARKLE_DIR" "$APP_DIR"; do
  codesign "${CODESIGN_OPTIONS[@]}" --sign "$CODESIGN_IDENTITY" "$code"
done
codesign --verify --deep --strict --verbose=2 "$APP_DIR"

echo "$APP_DIR"
