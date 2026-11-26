#!/bin/sh
# Fails on any top-level entry not listed in .ai/structure.txt. Ignored: .git, .build*, .DS_Store
# and anything gitignored (build/, private/, .vault-key). A new top-level folder needs owner review.
set -eu
cd "$(dirname "$0")/.."
LIST=".ai/structure.txt"
fail=0
for entry in $(/bin/ls -A); do
    case "$entry" in .git|.build*|.DS_Store) continue ;; esac
    git check-ignore -q "$entry" 2>/dev/null && continue
    if ! grep -v '^#' "$LIST" | grep -qxF "$entry"; then
        echo "structure: top-level '$entry' is not in $LIST. Put it in an existing folder (see AGENTS.md)." >&2
        fail=1
    fi
done
[ "$fail" = 0 ] && echo "ok: top-level layout matches $LIST"
exit "$fail"
