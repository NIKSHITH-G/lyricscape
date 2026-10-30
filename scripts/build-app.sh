#!/bin/zsh
# Builds Lyricscape and wraps it in a proper macOS app bundle at build/Lyricscape.app.
# Usage: scripts/build-app.sh [debug|release]   (default: debug)
set -euo pipefail
cd "${0:A:h}/.."

CONFIG="${1:-debug}"
APP="build/Lyricscape.app"

swift build -c "$CONFIG" --product Lyricscape
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Lyricscape" "$APP/Contents/MacOS/Lyricscape"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# Ad-hoc signature: enough to run locally and for macOS to remember permissions.
codesign --force --sign - --identifier app.lyricscape.Lyricscape "$APP"

echo "Built $APP ($CONFIG)"
