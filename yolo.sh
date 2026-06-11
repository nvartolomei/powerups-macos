#!/bin/bash

set -euo pipefail

echo "Building..."
xcodebuild \
    -workspace alt-tab-macos.xcworkspace \
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
