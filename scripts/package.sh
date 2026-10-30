#!/bin/zsh
# Builds an optimized Lyricscape.app and packages it as build/Lyricscape.zip and build/Lyricscape.dmg.
set -euo pipefail
cd "${0:A:h}/.."
scripts/build-app.sh release
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
rm -f build/Lyricscape.zip build/Lyricscape.dmg
ditto -c -k --keepParent build/Lyricscape.app build/Lyricscape.zip

# A DMG with the app and an Applications shortcut to drag it onto.
STAGE="$(mktemp -d)"
cp -R build/Lyricscape.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname "Lyricscape $VERSION" -srcfolder "$STAGE" -ov -format UDZO build/Lyricscape.dmg
rm -rf "$STAGE"
echo "Packaged build/Lyricscape.zip and build/Lyricscape.dmg (v$VERSION)"
