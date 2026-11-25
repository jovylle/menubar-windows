#!/bin/sh
# Packs build/<App>.app into build/<App>-<version>.dmg with an Applications shortcut.
# Uses only the built-in hdiutil. Run scripts/build-app.sh first.
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/scripts/app-info.sh"

APP="$ROOT/build/$APP_NAME.app"
if [ ! -d "$APP" ]; then
    echo "Missing $APP. Run scripts/build-app.sh first." >&2
    exit 1
fi

STAGE="$ROOT/build/dmg-stage"
DMG="$ROOT/build/$APP_NAME-$VERSION.dmg"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$APP_NAME $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
rm -rf "$STAGE"
hdiutil verify "$DMG" >/dev/null
echo "Built $DMG"
