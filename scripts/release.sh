#!/bin/zsh
# Builds a release zip and prints its SHA-256 (needed by the Homebrew cask).
#
#   ./scripts/release.sh              # build + zip + sha only
#   PUBLISH=1 ./scripts/release.sh    # also create the GitHub release via gh
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Support/Info.plist)
ZIP="build/AudioRouter-${VERSION}.zip"

./scripts/build-app.sh
rm -f "$ZIP"
ditto -c -k --keepParent build/AudioRouter.app "$ZIP"

SHA=$(shasum -a 256 "$ZIP" | awk '{print $1}')
echo ""
echo "zip:     $ZIP"
echo "sha256:  $SHA"
echo ""
echo "Update version + sha256 in the tap's Casks/audiorouter.rb after publishing."

if [ "${PUBLISH:-0}" = "1" ]; then
  gh release create "v${VERSION}" "$ZIP" --title "AudioRouter ${VERSION}" --generate-notes
fi
