#!/usr/bin/env bash
# Rebuild, quit any running copy, and launch the app bundle.
set -euo pipefail
cd "$(dirname "$0")/.."
scripts/build-app.sh
pkill -x NameShift || true
open build/NameShift.app
