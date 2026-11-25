#!/bin/sh
# Regenerates Resources/AppIcon.icns (and Resources/AppIcon-1024.png for docs and the site) from
# scripts/make-icon.swift. Uses only AppKit and the built-in iconutil. The outputs are committed, so
# this only needs to run when the design changes.
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$ROOT/build/icon"
rm -rf "$WORK"
mkdir -p "$WORK" "$ROOT/Resources"
swift "$ROOT/scripts/make-icon.swift" "$WORK/AppIcon.iconset"
iconutil --convert icns --output "$ROOT/Resources/AppIcon.icns" "$WORK/AppIcon.iconset"
cp "$WORK/AppIcon.iconset/icon_512x512@2x.png" "$ROOT/Resources/AppIcon-1024.png"
echo "Wrote $ROOT/Resources/AppIcon.icns"
