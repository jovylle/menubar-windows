#!/bin/sh
# Fails when the same block of 12 code lines appears twice in the Swift sources (Sources/, Tests/,
# scripts/*.swift). Lines are trimmed; blank lines, // comment lines and lines made only of brackets,
# commas or semicolons are skipped, so formatting changes do not hide a copy. Extract a shared
# function instead of copying code. Window size: DUP_LINES (default 12; never raise it to pass).
set -eu
cd "$(dirname "$0")/.."
W="${DUP_LINES:-12}"
dups=$(find Sources Tests scripts -name '*.swift' | sort | xargs awk -v W="$W" '
    FNR == 1 { n = 0 }
    {
        s = $0; sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s)
        if (s == "" || s ~ /^\/\// || s ~ /^[][(){},;]+$/) next
        n++; L[n] = s; P[n] = FNR
        if (n >= W) { k = ""; for (i = n - W + 1; i <= n; i++) k = k L[i] "\034"; print k "\035" FILENAME ":" P[n - W + 1] }
    }' | awk -F '\035' '{ c[$1]++; loc[$1] = loc[$1] " " $2 } END { for (k in c) if (c[k] > 1) print "  " c[k] " copies at" loc[k] }')
if [ -n "$dups" ]; then
    echo "duplicates: identical ${W}-line blocks found:" >&2
    echo "$dups" | sort >&2
    exit 1
fi
echo "ok: no duplicated ${W}-line Swift blocks"
