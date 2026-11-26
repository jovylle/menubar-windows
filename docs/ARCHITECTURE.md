# Architecture

MenubarWindows draws one tab per window inside the empty middle of the macOS menu bar. It reads
windows through CGWindowList and the Accessibility (AX) API, and raises them through AX. No network,
no dependencies, macOS 13+. Decisions: `docs/decisions/`.

## Targets and layers

| Layer | Path | May import | Role |
| --- | --- | --- | --- |
| Core | `Sources/MenubarWindowsCore/` | Foundation, CoreGraphics types | Pure logic: ordering, labels, focus rule, palette and contrast, window filter, demo data |
| App | `Sources/MenubarWindows/` | Core, AppKit, SwiftUI, ApplicationServices, Combine, ServiceManagement | Panels, refresh loop, AX and CG access, Settings UI, onboarding, demo mode, `--list` |
| Tests | `Tests/MenubarWindowsCoreTests/` | Core, Testing | Swift Testing tests for Core |
| Scripts | `scripts/` | system tools, Node built-ins | Build, release, screenshots, vault, checks. Leaf: nothing imports them |
| Site | `site/` | nothing | Static offline page. Leaf |
| Packaging | `packaging/homebrew/` | nothing | Cask, updated by `scripts/release.sh` |

Allowed directions: App -> Core. Tests -> Core. Nothing -> App. Core -> nothing (no package dependency).
`scripts/check-boundaries.sh` fails on any Core import other than Foundation or CoreGraphics, and on
any dependency given to Core in `Package.swift`. Existing violations would sit in
`.ai/boundary-allowlist.txt`, which is empty and may only shrink.

## Where new code goes

- A rule that can be decided from plain values (sizes, names, IDs, settings): Core, with tests.
- Anything touching NSWindow, NSScreen, AX, CGWindowList, SwiftUI or UserDefaults: App, kept thin,
  calling Core for the decision. Pattern: `WindowProvider.swift` reads AX, `WindowFilterRule.swift` decides.
- A new setting: `Sources/MenubarWindows/Settings.swift` (typed, `mw.` key), UI in `SettingsView.swift`.
- Anything shown in demo mode: names from `Sources/MenubarWindowsCore/DemoData.swift`.
- A new top-level folder: not without owner review and a line in `.ai/structure.txt`.

## Must never happen

- Core imports AppKit, SwiftUI, ApplicationServices, Combine or Cocoa, or the app target.
- Tabs ordered by CG z-order (reshuffles on every click).
- Network access, analytics, or a third-party dependency.
- Plaintext from `private/` or `.vault-key` in git. Real apps or titles in a committed screenshot.
- A check, test, baseline or CI step weakened to get green.

## Checks

`scripts/check.sh` runs, failing fast: `scripts/check-rules.sh`, `scripts/check-structure.sh`,
`scripts/check-boundaries.sh`, `scripts/check-escape-hatches.sh` (ratchet in `.ai/baseline.json`),
`scripts/check-duplicates.sh`, the vault check, a warnings-as-errors release build into `.build-check`,
`scripts/test.sh` into `.build-check-test`, the vault tests, and `scripts/check-weakening.sh`. The
pre-commit hook `scripts/hooks/pre-commit` runs the fast subset plus the vault check. CI:
`.github/workflows/check.yml`. Metrics: `scripts/audit.sh` writes `.ai/metrics.json` (weekly in CI).

`scripts/check-weakening.sh` compares against `CHECK_BASE` (default origin/main, else main). It fails on
new suppressions or escape hatches in added lines, skipped tests, deleted test files, fewer `@Test`
functions, a baseline number going up, an allowlist growing, or any edit to the check scripts, the
`.ai/` files, `Package.swift`, CI or CODEOWNERS, unless `ALLOW_CONFIG_CHANGE=1` (CI sets it when the PR
has the label `config-change`).

Not done yet, and what to add later:
- Dead code: no reliable offline tool ships with the toolchain. Add periphery when installs are allowed.
- Duplicates: `scripts/check-duplicates.sh` finds exact 12-line copies only. jscpd would also find
  near copies.
- Lint: no SwiftLint. Warnings-as-errors plus the ratchet stand in for it.

## Branch protection (to enable on GitHub by the owner)

On `main`: require a pull request, require the `check` status from `.github/workflows/check.yml`,
require review from code owners (`.github/CODEOWNERS`), block force pushes and deletion, and include
administrators. Create the label `config-change`.
