#!/bin/sh
# AI-durability audit, adapted from the ai-durability skill for Swift. Writes .ai/metrics.json and
# exits 1 if an escape-hatch or skipped-test count is above .ai/baseline.json or the rules are out of
# sync. Metrics should only go down or stay flat. Run weekly in CI (job audit) and before releases.
set -u
cd "$(dirname "$0")/.."
mkdir -p .ai
hatches=$(scripts/check-escape-hatches.sh --json | tr -d '{}')
swift_lines() { find "$1" -name '*.swift' -print0 | xargs -0 cat | wc -l | tr -d ' '; }
todo=$(grep -rEo 'TODO|FIXME' Sources Tests scripts site --include='*.swift' --include='*.sh' --include='*.mjs' --include='*.html' 2>/dev/null | wc -l | tr -d ' ')
swift_tests=$(grep -rhoE '@Test' Tests 2>/dev/null | wc -l | tr -d ' ')
node_tests=$(grep -rhoE '^test\(' Tests 2>/dev/null | wc -l | tr -d ' ')
rules_sync=ok
scripts/check-rules.sh >/dev/null 2>&1 || rules_sync=FAILED
cfg_changed=$(git log --since='30 days ago' --name-only --pretty=format: 2>/dev/null \
    | grep -E '^(Package\.swift|scripts/check|scripts/hooks|\.ai/|\.github/)' | sort -u | wc -l | tr -d ' ')
cat > .ai/metrics.json <<J
{$hatches,"todo_fixme":$todo,"lines.core":$(swift_lines Sources/MenubarWindowsCore),"lines.app":$(swift_lines Sources/MenubarWindows),"lines.tests":$(swift_lines Tests),"tests.swift_count":$swift_tests,"tests.node_count":$node_tests,"config_files_changed_30d":$cfg_changed,"rules_sync":"$rules_sync"}
J
cat .ai/metrics.json
fail=0
[ "$rules_sync" = ok ] || { echo "FAIL: rules_sync=$rules_sync (run scripts/check-rules.sh)"; fail=1; }
scripts/check-escape-hatches.sh >/dev/null || { echo "FAIL: escape hatches above baseline (run scripts/check-escape-hatches.sh)"; fail=1; }
exit $fail
