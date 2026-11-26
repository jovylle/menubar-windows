#!/bin/sh
# Layer check: Sources/MenubarWindowsCore/ is pure logic. It may import Foundation and CoreGraphics only.
# Fails on any other import (AppKit, SwiftUI, ApplicationServices, Combine, Cocoa, ...) that is not
# listed in .ai/boundary-allowlist.txt, and on Core importing the app target. The allowlist may only
# shrink. Also fails if Package.swift gives Core a dependency. See docs/ARCHITECTURE.md.
set -eu
cd "$(dirname "$0")/.."
CORE="Sources/MenubarWindowsCore"
ALLOWLIST=".ai/boundary-allowlist.txt"
ALLOWED_RE='^(Foundation|CoreGraphics)$'

fail=0
found=$(grep -rnE '^[[:space:]]*(@[A-Za-z_]+[[:space:]]+)*import[[:space:]]+([a-z]+[[:space:]]+)?[A-Za-z_][A-Za-z0-9_.]*' \
    --include='*.swift' "$CORE" || true)
echo "$found" | while IFS= read -r line; do
    [ -n "$line" ] || continue
    file=${line%%:*}
    module=$(echo "$line" | sed -E 's/^[^:]*:[0-9]+:[[:space:]]*(@[A-Za-z_]+[[:space:]]+)*import[[:space:]]+([a-z]+[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*).*/\3/')
    echo "$module" | grep -qE "$ALLOWED_RE" && continue
    if grep -qxF "$file: import $module" "$ALLOWLIST" 2>/dev/null; then continue; fi
    echo "boundaries: $file imports $module. Core may import only Foundation and CoreGraphics." >&2
    echo x
done | grep -q x && fail=1

# Core must stay dependency-free in Package.swift: its .target(...) block has no dependencies.
if awk '/name: "MenubarWindowsCore"/ { inside = 1 } inside && /dependencies:/ { bad = 1 } inside && /\)/ { inside = 0 } END { exit !bad }' Package.swift; then
    echo "boundaries: Package.swift gives MenubarWindowsCore a dependency. Core depends on nothing." >&2
    fail=1
fi
[ "$fail" = 0 ] && echo "ok: Core imports only Foundation and CoreGraphics"
exit "$fail"
