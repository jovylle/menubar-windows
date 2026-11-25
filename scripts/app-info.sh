#!/bin/sh
# Source this file to get APP_NAME, BUNDLE_ID, TAGLINE and VERSION.
# The values live in Sources/MenubarWindows/AppInfo.swift (the single source of truth) and VERSION.
ROOT="${ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
INFO="$ROOT/Sources/MenubarWindows/AppInfo.swift"
_read() { sed -n "s/^ *static let $1 = \"\(.*\)\"$/\1/p" "$INFO" | head -n 1; }
APP_NAME="$(_read displayName)"
BUNDLE_ID="$(_read bundleIdentifier)"
TAGLINE="$(_read tagline)"
VERSION="$(tr -d ' \n' < "$ROOT/VERSION")"
EXECUTABLE="MenubarWindows"
if [ -z "$APP_NAME" ] || [ -z "$BUNDLE_ID" ] || [ -z "$VERSION" ]; then
    echo "app-info.sh: could not read app info from $INFO or VERSION" >&2
    exit 1
fi
