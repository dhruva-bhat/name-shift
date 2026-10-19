#!/usr/bin/env bash
# Regenerate Resources/AppIcon.icns from the SwiftUI icon drawing (debug-build render hook).
set -euo pipefail
cd "$(dirname "$0")/.."
swift build
ICONSET="build/AppIcon.iconset"
rm -rf "$ICONSET"
"$(swift build --show-bin-path)/NameShift" --render-app-icon "$ICONSET"
iconutil -c icns -o Resources/AppIcon.icns "$ICONSET"
echo "Wrote Resources/AppIcon.icns"
