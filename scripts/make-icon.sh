#!/bin/zsh
# Regenerates Resources/AppIcon.icns from scripts/assets/make-icon.swift.
set -euo pipefail
cd "${0:A:h}/.."
TMP="$(mktemp -d)"
swift scripts/assets/make-icon.swift "$TMP/icon.png"
mkdir -p "$TMP/AppIcon.iconset"
for s in 16 32 128 256 512; do
  sips -z $s $s "$TMP/icon.png" --out "$TMP/AppIcon.iconset/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) "$TMP/icon.png" --out "$TMP/AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$TMP/AppIcon.iconset" -o Resources/AppIcon.icns
cp "$TMP/icon.png" Resources/AppIcon.png
echo "Wrote Resources/AppIcon.icns"
