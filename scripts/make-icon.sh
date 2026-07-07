#!/bin/zsh
# Regenerates Support/AppIcon.icns from Support/AppIcon.svg.
# Renders with headless Chrome (keeps transparency + SVG filters).
set -euo pipefail

cd "$(dirname "$0")/.."

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
  --headless --disable-gpu --hide-scrollbars \
  --default-background-color=00000000 \
  --window-size=1024,1024 \
  --user-data-dir="$WORK/chrome-profile" \
  --screenshot="$WORK/AppIcon-1024.png" \
  "file://$PWD/Support/AppIcon.svg"

SET="$WORK/AppIcon.iconset"
mkdir -p "$SET"
for s in 16 32 128 256 512; do
  sips -z $s $s "$WORK/AppIcon-1024.png" --out "$SET/icon_${s}x${s}.png" >/dev/null
  d=$((s * 2))
  sips -z $d $d "$WORK/AppIcon-1024.png" --out "$SET/icon_${s}x${s}@2x.png" >/dev/null
done

iconutil -c icns "$SET" -o Support/AppIcon.icns
echo "Regenerated Support/AppIcon.icns"
