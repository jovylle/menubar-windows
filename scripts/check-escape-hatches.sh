#!/bin/sh
# Ratchet on Swift escape hatches in Sources/. Fails when any count rises above .ai/baseline.json.
#
#   scripts/check-escape-hatches.sh          check against the baseline
#   scripts/check-escape-hatches.sh --json   print the current counts as JSON (used by scripts/audit.sh)
#
# Counted per target (core = Sources/MenubarWindowsCore, app = Sources/MenubarWindows):
#   try!  as!  unsafeBitCast  @unchecked Sendable  nonisolated(unsafe)  @preconcurrency
#   swiftlint:disable  and postfix ! (force unwraps and implicitly unwrapped optionals).
# Also tests.skipped: XCTSkip, .disabled, .skip( / .todo( and { skip / { todo options in Tests/.
# Gotchas:
# - Code patterns are counted after string literals and // comments are stripped, so docs that mention
#   `try!` do not count. swiftlint:disable lives in comments, so it is counted on the raw text.
# - The force-unwrap count is a heuristic: a ! directly after an identifier, ), ], > or ?, with !=,
#   as! and try! removed first. Block comments and multi-line strings are not stripped.
# - The baseline only goes down. Lower it after removing escape hatches; never raise it.
set -eu
cd "$(dirname "$0")/.."
BASELINE=".ai/baseline.json"

strip() { # code without string literals and line comments
    find "$1" -name '*.swift' -print0 | xargs -0 cat | sed -E 's/"([^"\\]|\\.)*"/""/g; s,//.*$,,'
}
fixed() { strip "$1" | grep -oF -- "$2" | wc -l | tr -d ' '; }
raw() { find "$1" -name '*.swift' -print0 | xargs -0 cat | grep -oF -- "$2" | wc -l | tr -d ' '; }
bang() { strip "$1" | sed -E 's/!=//g; s/as!//g; s/try!//g' | grep -oE '[A-Za-z0-9_)>?]!|\]!' | wc -l | tr -d ' '; }

counts() { # <prefix> <dir>
    printf '"%s.try_bang":%s,' "$1" "$(fixed "$2" 'try!')"
    printf '"%s.as_bang":%s,' "$1" "$(fixed "$2" 'as!')"
    printf '"%s.unsafe_bit_cast":%s,' "$1" "$(fixed "$2" 'unsafeBitCast')"
    printf '"%s.unchecked_sendable":%s,' "$1" "$(fixed "$2" '@unchecked Sendable')"
    printf '"%s.nonisolated_unsafe":%s,' "$1" "$(fixed "$2" 'nonisolated(unsafe)')"
    printf '"%s.preconcurrency":%s,' "$1" "$(fixed "$2" '@preconcurrency')"
    printf '"%s.swiftlint_disable":%s,' "$1" "$(raw "$2" 'swiftlint:disable')"
    printf '"%s.force_unwrap":%s' "$1" "$(bang "$2")"
}
skipped() {
    grep -rEo 'XCTSkip|\.disabled|\.(skip|todo)\(|[{,] *(skip|todo) *:' Tests 2>/dev/null | wc -l | tr -d ' '
}
CURRENT="{$(counts core Sources/MenubarWindowsCore),$(counts app Sources/MenubarWindows),\"tests.skipped\":$(skipped)}"

if [ "${1:-}" = "--json" ]; then echo "$CURRENT"; exit 0; fi
[ -f "$BASELINE" ] || { echo "escape hatches: missing $BASELINE" >&2; exit 1; }

fail=0
for pair in $(echo "$CURRENT" | tr -d '{}' | tr ',' ' '); do
    key=$(echo "$pair" | cut -d: -f1 | tr -d '"')
    cur=$(echo "$pair" | cut -d: -f2)
    base=$(grep -o "\"$key\": *[0-9]*" "$BASELINE" | grep -o '[0-9]*$' || true)
    if [ -z "$base" ]; then
        echo "escape hatches: $key has no baseline in $BASELINE" >&2; fail=1
    elif [ "$cur" -gt "$base" ]; then
        echo "escape hatches: $key rose from $base to $cur. Remove the new one; do not raise the baseline." >&2
        fail=1
    elif [ "$cur" -lt "$base" ]; then
        echo "escape hatches: $key fell from $base to $cur. Lower it in $BASELINE."
    fi
done
[ "$fail" = 0 ] && echo "ok: escape hatches at or below baseline"
exit "$fail"
