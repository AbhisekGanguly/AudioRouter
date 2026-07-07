#!/bin/zsh
# Builds AudioRouter.app: swift build → assemble bundle → codesign.
#
# Usage:
#   ./scripts/build-app.sh                 # ad-hoc signed (development)
#   SIGN_IDENTITY="Developer ID Application: ..." ./scripts/build-app.sh
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
APP="build/AudioRouter.app"

swift build -c "$CONFIG"

BIN="$(swift build -c "$CONFIG" --show-bin-path)/AudioRouter"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/AudioRouter"
cp Support/Info.plist "$APP/Contents/Info.plist"
[ -f Support/AppIcon.icns ] && cp Support/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

codesign --force --sign "$SIGN_IDENTITY" \
  --entitlements Support/AudioRouter.entitlements \
  --options runtime \
  "$APP" 2>/dev/null || \
codesign --force --sign "$SIGN_IDENTITY" \
  --entitlements Support/AudioRouter.entitlements \
  "$APP"

echo "Built: $APP"
codesign -dv "$APP" 2>&1 | grep -E "Signature|TeamIdentifier" || true
