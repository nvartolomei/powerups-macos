#!/usr/bin/env bash

set -ex

xcodebuild -version
xcodebuild -workspace powerups-macos.xcworkspace -scheme Release -showBuildSettings | grep SWIFT_VERSION

set -o pipefail && xcodebuild test -workspace powerups-macos.xcworkspace -scheme Test -configuration Release
