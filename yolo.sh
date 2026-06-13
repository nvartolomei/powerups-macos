#!/bin/bash

set -euo pipefail

# Build a version string: "<date> <time> <commit>[-dirty]"
BUILD_DATE=$(date '+%Y-%m-%d %H:%M:%S')
COMMIT=$(git rev-parse --short HEAD)
if [ -n "$(git status --porcelain)" ]; then
    COMMIT="${COMMIT}-dirty"
fi
VERSION="${BUILD_DATE} ${COMMIT}"
echo "Version: ${VERSION}"

# Substitute #VERSION# placeholder in Info.plist, restoring it on exit so the
# working tree stays clean regardless of how the build exits.
cp Info.plist Info.plist.bak
trap 'mv Info.plist.bak Info.plist' EXIT
sed -i '' "s|#VERSION#|${VERSION}|g" Info.plist

echo "Building..."
xcodebuild \
    -workspace powerups-macos.xcworkspace \
    -scheme Release \
    -derivedDataPath DerivedData \
    CODE_SIGN_IDENTITY="Local Self-Signed" \
    OTHER_CODE_SIGN_FLAGS="--timestamp=none --deep --options runtime" \
    build

echo "Overwriting existing install..."
osascript -e 'quit app "PowerUps"' 2>/dev/null
rm -rf /Applications/PowerUps.app
cp -R DerivedData/Build/Products/Release/PowerUps.app /Applications/
open /Applications/PowerUps.app
