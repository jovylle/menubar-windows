#!/bin/sh
# The one check. Runs every gate in order and stops at the first failure. Run it before handing back
# any change; CI runs it on every pull request and on pushes to main.
# Builds go to .build-check and .build-check-test, never .build/release, so a running copy of the app
# built there is not disturbed. Set CHECK_BASE to compare the weakening gate with another ref.
set -eu
cd "$(dirname "$0")/.."
step() { # <name> <command...>
    name="$1"; shift
    echo "==> $name"
    if ! "$@"; then
        echo "FAILED: $name. Fix the code, not the check (see AGENTS.md)." >&2
        exit 1
    fi
}
step "rules sync"     scripts/check-rules.sh
step "structure"      scripts/check-structure.sh
step "boundaries"     scripts/check-boundaries.sh
step "escape hatches" scripts/check-escape-hatches.sh
step "duplicates"     scripts/check-duplicates.sh
step "vault check"    node scripts/vault.mjs check
step "build (warnings are errors)" swift build -c release -Xswiftc -warnings-as-errors --scratch-path .build-check
step "swift tests"    scripts/test.sh --scratch-path .build-check-test
step "vault tests"    node --test Tests/vault.test.mjs
step "anti-weakening" scripts/check-weakening.sh
echo "ok: all checks passed"
