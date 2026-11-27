#!/bin/sh
# Builds build/<App>.app: release binary, Info.plist, icon, code signature.
# Name, bundle id and tagline come from Sources/MenubarWindows/AppInfo.swift (via app-info.sh),
# the version from VERSION.
#
# Without MW_SIGN_IDENTITY the signature is ad-hoc (`codesign -s -`): enough to run on this Mac, but
# macOS ties the Accessibility grant to the exact binary, so every new build asks for it again.
# With MW_SIGN_IDENTITY (a certificate name or hash; CI sets it from the MW_SIGN_P12 secret) every
# build carries the same certificate, so the grant survives updates. MW_SIGN_KEYCHAIN optionally
# names the keychain that holds it. Distributing to other Macs without Gatekeeper warnings needs a
# Developer ID certificate and notarization; see "Release checklist" in README.md.
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/scripts/app-info.sh"

cd "$ROOT"
swift build -c release
BIN="$(swift build -c release --show-bin-path)/$EXECUTABLE"

APP="$ROOT/build/$APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$EXECUTABLE"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

YEAR="$(date +%Y)"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleExecutable</key>
    <string>$EXECUTABLE</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_NUMBER:-$VERSION}</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.productivity</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © $YEAR Jovylle Bermudez. MIT License.</string>
</dict>
</plist>
PLIST
plutil -lint "$APP/Contents/Info.plist" >/dev/null

if [ -n "${MW_SIGN_IDENTITY:-}" ]; then
    if [ -n "${MW_SIGN_KEYCHAIN:-}" ]; then
        codesign --force --deep -s "$MW_SIGN_IDENTITY" --keychain "$MW_SIGN_KEYCHAIN" "$APP"
    else
        codesign --force --deep -s "$MW_SIGN_IDENTITY" "$APP"
    fi
    SIGNED="signed with $MW_SIGN_IDENTITY"
else
    codesign --force --deep -s - "$APP"
    SIGNED="ad-hoc signed"
fi
codesign --verify --deep --strict "$APP"
echo "Built $APP ($APP_NAME $VERSION, $BUNDLE_ID), $SIGNED."
