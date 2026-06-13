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

# Build the Quick Look preview bundle (single self-contained preview.html) that
# the QuickLookMarkdown extension embeds. Must precede xcodebuild so the
# extension's Copy Resources phase finds the file.
echo "Building Quick Look preview bundle..."
if [ ! -d src/quicklook-markdown/web/node_modules ]; then
    npm --prefix src/quicklook-markdown/web ci
fi
npm --prefix src/quicklook-markdown/web run build

# Substitute #VERSION# in the app and extension Info.plist for the build, then
# restore the templates from git on exit. Restoring from git (rather than a .bak
# copy) is robust even if a prior run was interrupted and left a substituted
# value behind, so the placeholder never leaks into a commit.
trap 'git checkout -- Info.plist src/quicklook-markdown/Info.plist' EXIT
sed -i '' "s|#VERSION#|${VERSION}|g" Info.plist
sed -i '' "s|#VERSION#|${VERSION}|g" src/quicklook-markdown/Info.plist

# Run the unit tests before building so a broken build never reaches
# /Applications.
echo "Running tests..."
xcodebuild \
    -workspace powerups-macos.xcworkspace \
    -scheme Test \
    -derivedDataPath DerivedData \
    test

# The Release scheme builds the QuickLookMarkdown.appex as a dependency and
# embeds it into PowerUps.app/Contents/PlugIns; CODE_SIGN_IDENTITY signs it with
# the same self-signed cert as the app. No --deep: it would re-sign the appex
# with the app's entitlements and strip its sandbox, which pkd then rejects.
echo "Building..."
xcodebuild \
    -workspace powerups-macos.xcworkspace \
    -scheme Release \
    -derivedDataPath DerivedData \
    CODE_SIGN_IDENTITY="Local Self-Signed" \
    OTHER_CODE_SIGN_FLAGS="--timestamp=none --options runtime" \
    build

echo "Overwriting existing install..."
osascript -e 'quit app "PowerUps"' 2>/dev/null
rm -rf /Applications/PowerUps.app
cp -R DerivedData/Build/Products/Release/PowerUps.app /Applications/

# Register the app (and its embedded Quick Look extension) with Launch Services,
# enable the preview extension, and reset the Quick Look cache so the new build
# is picked up immediately when pressing space in Finder.
echo "Registering Quick Look extension..."
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/PowerUps.app
pluginkit -e use -i com.nvartolomei.powerups.quicklook-markdown 2>/dev/null || true
qlmanage -r >/dev/null 2>&1 || true
qlmanage -r cache >/dev/null 2>&1 || true

open /Applications/PowerUps.app

echo "Done!"
