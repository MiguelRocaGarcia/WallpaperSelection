#!/bin/zsh
# Resets a simulator and fills its Photos library with the test fixtures.
# Usage: scripts/seed-simulator.sh <simulator-udid>
set -euo pipefail
UDID=${1:?simulator UDID required}
ROOT=${0:A:h:h}
BUNDLE=com.miguelroca.wallpaperselection

xcrun simctl shutdown "$UDID" 2>/dev/null || true
xcrun simctl erase "$UDID"
xcrun simctl boot "$UDID"
xcrun simctl bootstatus "$UDID" -b >/dev/null
xcrun simctl addmedia "$UDID" "$ROOT"/WallpaperSelectionTests/Fixtures/*/*.jpg
xcrun simctl privacy "$UDID" grant photos "$BUNDLE"
echo "Seeded $(ls "$ROOT"/WallpaperSelectionTests/Fixtures/*/*.jpg | wc -l | tr -d ' ') photos into $UDID"
