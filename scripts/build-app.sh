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
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Ad-hoc sign so the app launches locally with a stable identity.
codesign --force --sign - --options runtime "$APP"

echo "Built $APP"
