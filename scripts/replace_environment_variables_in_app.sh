#!/usr/bin/env bash

set -exu

version="$(cat "$VERSION_FILE")"

sed -i '' -e "s/#VERSION#/$version/" Info.plist
