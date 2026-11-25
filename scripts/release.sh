#!/bin/sh
# Builds the app and the dmg, then prints what a release needs and updates the Homebrew cask.
# Offline: it never uploads, signs with a real identity, or notarizes. Those steps are listed at the end.
#
# Usage: scripts/release.sh
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/scripts/app-info.sh"

"$ROOT/scripts/build-app.sh"
"$ROOT/scripts/make-dmg.sh"

DMG="$ROOT/build/$APP_NAME-$VERSION.dmg"
SHA="$(shasum -a 256 "$DMG" | awk '{print $1}')"
CASK="$ROOT/packaging/homebrew/Casks/menubarwindows.rb"

# Point the cask at this version and checksum. The sed edits are in place and portable to macOS.
sed -i '' -e "s/^  version \".*\"/  version \"$VERSION\"/" \
          -e "s/^  sha256 \".*\"/  sha256 \"$SHA\"/" "$CASK"

echo
echo "dmg:    $DMG"
echo "sha256: $SHA"
echo "cask:   $CASK (version and sha256 updated)"
echo
echo "Still to do by hand (see packaging/homebrew/README.md):"
echo "  1. Sign with a Developer ID certificate and notarize the app, then rebuild the dmg."
echo "  2. Create a GitHub release tagged v$VERSION and upload the dmg."
echo "  3. Copy the cask into the tap repo (jovylle/homebrew-tap, folder Casks/) and push."
