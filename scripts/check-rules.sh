#!/bin/sh
# Agent rules sync: CLAUDE.md -> AGENTS.md, .claude/skills and .kiro/skills -> ../.agents/skills, and
# every path named in inline backticks in AGENTS.md and docs/ARCHITECTURE.md still exists.
# A backticked token counts as a path when it has no spaces and contains a / or ends in a known file
# extension. Bare file names (`Package.swift`, `AppInfo.swift`) must match a tracked file anywhere.
# Gitignored paths (private/, build/) and fenced code blocks are skipped.
set -eu
cd "$(dirname "$0")/.."
fail=0
link() { # <path> <target>
    if [ ! -L "$1" ] || [ "$(readlink "$1")" != "$2" ]; then
        echo "rules: $1 must be a symlink to $2" >&2; fail=1
    elif [ ! -e "$1" ]; then
        echo "rules: $1 -> $2 does not resolve" >&2; fail=1
    fi
}
link CLAUDE.md AGENTS.md
link .claude/skills ../.agents/skills
link .kiro/skills ../.agents/skills
for skill in .agents/skills/*/; do
    [ -f "${skill}SKILL.md" ] || { echo "rules: ${skill} has no SKILL.md" >&2; fail=1; }
done

EXT='(md|swift|sh|mjs|js|json|txt|rb|yml|yaml|html|png|icns)'
for doc in AGENTS.md docs/ARCHITECTURE.md; do
    [ -f "$doc" ] || { echo "rules: missing $doc" >&2; fail=1; continue; }
    paths=$(awk '/^```/ { fenced = !fenced; next } !fenced' "$doc" | grep -oE '`[^` ]+`' | tr -d '`' | sort -u)
    for p in $paths; do
        case "$p" in -*|*\(*|*\**|*\<*|*'$'*) continue ;; esac
        if echo "$p" | grep -q /; then
            clean=${p%/}
            [ -e "$clean" ] && continue
            { git check-ignore -q "$clean" || git check-ignore -q "$clean/"; } 2>/dev/null && continue
            echo "rules: $doc names \`$p\`, which does not exist" >&2; fail=1
        elif echo "$p" | grep -qE "^[A-Za-z0-9_.-]+\.$EXT\$"; then
            [ -e "$p" ] && continue
            git ls-files | grep -qE "(^|/)$(echo "$p" | sed 's/\./\\./g')\$" && continue
            echo "rules: $doc names \`$p\`, which matches no tracked file" >&2; fail=1
        fi
    done
done
[ "$fail" = 0 ] && echo "ok: rules files linked, named paths exist"
exit "$fail"
