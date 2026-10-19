#!/usr/bin/env bash
# Builds build/NameShift.app from the SwiftPM executable.
#   CONFIG=release scripts/build-app.sh
#   SIGN_IDENTITY="Apple Development: you@example.com (TEAMID)" scripts/build-app.sh
#
# Signing matters for testing: macOS ties Input Monitoring / Accessibility grants to the code
# signature. Ad-hoc signatures change on every build, so grants silently stop working after a
# rebuild. Any stable identity (a free "Apple Development" cert from Xcode, or a self-signed
# "NameShift Dev" code-signing cert from Keychain Access) avoids that.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-debug}"
swift build -c "$CONFIG"
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

APP="build/NameShift.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/NameShift" "$APP/Contents/MacOS/NameShift"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

IDENTITY="${SIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" ]]; then
  IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
    | grep -Eo '"(Developer ID Application|Apple Development|NameShift Dev)[^"]*"' | head -1 | tr -d '"' || true)"
fi
if [[ -z "$IDENTITY" ]]; then
  # A self-signed cert isn't "valid" (trusted) so -v hides it, but it signs fine and gives TCC a
  # stable identity, which is all local testing needs.
  IDENTITY="$(security find-identity -p codesigning 2>/dev/null \
    | grep -Eo '"NameShift Dev"' | head -1 | tr -d '"' || true)"
fi
if [[ -z "$IDENTITY" ]]; then
  echo "warning: no signing identity found; signing ad-hoc. Permissions will need re-granting after each rebuild." >&2
  IDENTITY="-"
fi

codesign --force --options runtime --entitlements Resources/NameShift.entitlements --sign "$IDENTITY" "$APP"
echo "Built $APP (signed: $IDENTITY)"
