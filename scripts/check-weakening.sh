#!/bin/sh
# Anti-weakening gate: compares the working tree (committed, staged, unstaged and untracked files)
# with a base ref and fails when the change makes the checks weaker:
#   - added lines with a suppression or a skipped or disabled test (swiftlint:disable, XCTSkip,
#     .disabled, @Test(.disabled, .skip( / .todo(, { skip: / { todo:, eslint-disable, @ts-ignore,
#     shellcheck disable, -suppress-warnings, -warnings-as-errors removed)
#   - a deleted test file, or fewer @Test functions or node test( calls than the base
#   - a number in .ai/baseline.json going up or a key removed; lines added to .ai/boundary-allowlist.txt
#   - any change or deletion of a protected file that exists in the base: scripts/check*.sh,
#     scripts/test.sh, scripts/audit.sh, scripts/hooks/*, .ai/structure.txt, Package.swift,
#     .github/workflows/*, .github/CODEOWNERS
# ALLOW_CONFIG_CHANGE=1 skips only the protected-file rule (CI sets it for PRs labelled config-change).
# Base: CHECK_BASE, else origin/main, else main; the merge base with HEAD is used.
# Gotcha: CI must check out with fetch-depth 0, or the base ref is missing and this fails.
set -eu
cd "$(dirname "$0")/.."

REF="${CHECK_BASE:-}"
if [ -z "$REF" ]; then
    if git rev-parse --verify -q origin/main >/dev/null; then REF=origin/main; else REF=main; fi
fi
git rev-parse --verify -q "$REF^{commit}" >/dev/null || { echo "weakening: base ref '$REF' not found (fetch-depth 0?)" >&2; exit 1; }
BASE=$(git merge-base "$REF" HEAD 2>/dev/null || git rev-parse "$REF")
fail=0
bad() { echo "weakening: $*" >&2; fail=1; }

# 1. Suppressions anywhere and skips in Tests/, in added lines (tracked diffs plus untracked files).
# The check scripts and the audit name these patterns themselves; they are protected files instead.
SUPPRESS='swiftlint:disable|eslint-disable|@ts-ignore|shellcheck disable|-suppress-warnings'
SKIP='XCTSkip|\.disabled|\.(skip|todo)\(|[{,] *(skip|todo) *:'
lines=$( {
    git diff "$BASE" --no-color -U0 -- . ':(exclude)scripts/check*.sh' ':(exclude)scripts/audit.sh' \
        | awk '/^\+\+\+ / { f = substr($0, 7); next } /^\+/ { print f ": " substr($0, 2) }'
    git ls-files --others --exclude-standard | while IFS= read -r f; do
        if echo "$f" | grep -qE '^scripts/(check.*\.sh|audit\.sh)$|\.md$'; then continue; fi
        [ -f "$f" ] && grep -I '' "$f" 2>/dev/null | sed "s|^|$f: |"
    done
} | grep -vE '^[^:]*\.md: ' || true)
added=$(echo "$lines" | grep -E "$SUPPRESS" || true)
[ -n "$added" ] && bad "added suppressions:
$added"
added=$(echo "$lines" | grep -E '^Tests/' | grep -E "$SKIP" || true)
[ -n "$added" ] && bad "added skipped or disabled tests:
$added"

removed_flag=$(git diff "$BASE" --no-color -U0 -- scripts .github | grep -E '^-[^-].*-warnings-as-errors' || true)
[ -n "$removed_flag" ] && bad "a -warnings-as-errors flag was removed:
$removed_flag"

# 2. Deleted test files and fewer tests.
deleted=$(git diff "$BASE" --name-only --diff-filter=D -M -- Tests || true)
[ -n "$deleted" ] && bad "deleted test files: $deleted"
count_base() { git grep -hoE "$1" "$BASE" -- Tests 2>/dev/null | wc -l | tr -d ' '; }
count_now() { grep -rhoE "$1" Tests 2>/dev/null | wc -l | tr -d ' '; }
for p in '@Test' '^test\('; do
    b=$(count_base "$p"); n=$(count_now "$p")
    [ "$n" -lt "$b" ] && bad "tests matching '$p' fell from $b to $n"
done

# 3. Baseline and allowlist only shrink.
if git cat-file -e "$BASE:.ai/baseline.json" 2>/dev/null; then
    for pair in $(git show "$BASE:.ai/baseline.json" | grep -oE '"[a-z_.]+": *[0-9]+' | tr -d ' "'); do
        key=${pair%%:*}; was=${pair##*:}
        now=$(grep -oE "\"$key\": *[0-9]+" .ai/baseline.json 2>/dev/null | grep -oE '[0-9]+$' || true)
        if [ -z "$now" ]; then bad ".ai/baseline.json lost key $key"
        elif [ "$now" -gt "$was" ]; then bad ".ai/baseline.json $key went up from $was to $now"; fi
    done
fi
if git cat-file -e "$BASE:.ai/boundary-allowlist.txt" 2>/dev/null; then
    grown=$(git diff "$BASE" --no-color -U0 -- .ai/boundary-allowlist.txt | grep -E '^\+[^+#]' || true)
    [ -n "$grown" ] && bad ".ai/boundary-allowlist.txt grew: $grown"
fi

# 4. Protected files that already exist in the base.
if [ "${ALLOW_CONFIG_CHANGE:-0}" != 1 ]; then
    changed=$(git diff "$BASE" --name-only -- 'scripts/check*.sh' scripts/test.sh scripts/audit.sh 'scripts/hooks/*' \
        .ai/structure.txt Package.swift '.github/workflows/*' .github/CODEOWNERS || true)
    for f in $changed; do
        git cat-file -e "$BASE:$f" 2>/dev/null && bad "$f changed. Checks and config change only in a PR labelled config-change (ALLOW_CONFIG_CHANGE=1)."
    done
fi

[ "$fail" = 0 ] && echo "ok: nothing weakened against $REF ($(git rev-parse --short "$BASE"))"
exit "$fail"
