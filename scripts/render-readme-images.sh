#!/usr/bin/env bash
# Re-render the README images (docs/images/*-light.png / *-dark.png) from the app's real views.
set -euo pipefail
cd "$(dirname "$0")/.."
swift build
rm -rf docs/images
"$(swift build --show-bin-path)/NameShift" --render-readme-images docs/images
