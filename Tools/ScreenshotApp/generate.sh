#!/bin/bash
# Generates README screenshots from the package's SwiftUI control views.
# Copies the library sources in (single source of truth in ../../Sources),
# builds the macOS renderer, and writes PNGs to <repo>/Screenshots.
set -euo pipefail

cd "$(dirname "$0")"
REPO_ROOT="$(cd ../.. && pwd)"
LIB_SRC="$REPO_ROOT/Sources/DicyaninMockHandTracking"
LIB_DST="Sources/ScreenshotApp/Lib"

rm -rf "$LIB_DST"
mkdir -p "$LIB_DST"
cp "$LIB_SRC"/*.swift "$LIB_DST"/

swift run ScreenshotApp "$REPO_ROOT"

echo "Done. PNGs in $REPO_ROOT/Screenshots"
