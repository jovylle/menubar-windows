#!/bin/sh
# Runs the unit tests offline. With only the Command Line Tools installed (no Xcode selected),
# SwiftPM does not find the bundled Swift Testing framework on its own, so pass its paths.
set -eu
cd "$(dirname "$0")/.."
DEV="$(xcode-select -p)"
F="$DEV/Library/Developer/Frameworks"
L="$DEV/Library/Developer/usr/lib"
if [ -d "$F/Testing.framework" ]; then
    exec swift test -Xswiftc "-F$F" -Xlinker "-F$F" -Xlinker -rpath -Xlinker "$F" -Xlinker -rpath -Xlinker "$L" "$@"
fi
exec swift test "$@"
