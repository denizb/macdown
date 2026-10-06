#!/bin/zsh
# Builds MacDown.app into ./build. Usage: scripts/build-app.sh [debug|release]
set -euo pipefail

CONFIG="${1:-release}"
ROOT="${0:A:h:h}"
APP="$ROOT/build/MacDown.app"

cd "$ROOT"
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/MacDown"

[[ -f Resources/AppIcon.icns ]] || swift scripts/make-icon.swift Resources/AppIcon.icns

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/MacDown"

# SwiftPM records the deployment target as the SDK version, and macOS only gives apps
# linked against SDK 26+ the Liquid Glass design. Stamp the SDK we actually built with.
MIN_OS="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' Resources/Info.plist)"
vtool -set-build-version macos "$MIN_OS" "$(xcrun --show-sdk-version)" -replace \
    -output "$APP/Contents/MacOS/MacDown" "$APP/Contents/MacOS/MacDown" 2>/dev/null
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Ad-hoc sign so the app launches locally with a stable identity.
codesign --force --sign - --options runtime "$APP"

echo "Built $APP"
