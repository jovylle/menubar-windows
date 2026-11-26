# AGENTS.md

MenubarWindows: a macOS 13+ menu bar app (Swift package, MIT, no dependencies) that draws one tab per
window inside the empty middle of the menu bar. Autonomy mode is NOT on by default in this repo: ask
before commits, pushes, releases, or anything outside the task.

## Before you finish any change

Run `scripts/check.sh` and make it pass. It runs rules sync, structure, boundaries, escape hatches,
duplicates, vault check, a warnings-as-errors build, Swift tests, vault tests and the anti-weakening gate.

## Folder map

- `Sources/MenubarWindowsCore/`: pure logic (ordering, labels, focus, palette, filter, demo data). Unit tested.
- `Sources/MenubarWindows/`: the app (AppKit, SwiftUI, Accessibility). `AppInfo.swift` holds name, bundle id, tagline.
- `Tests/MenubarWindowsCoreTests/`: Swift Testing tests for Core. `Tests/vault.test.mjs`: vault tests.
- `scripts/`: build, test, release, screenshot, vault and check scripts. `scripts/hooks/pre-commit`.
- `Resources/`: generated app icon (committed). `assets/screenshots/`: demo-mode captures (committed).
- `site/`: static offline landing page. `packaging/homebrew/`: the cask.
- `docs/ARCHITECTURE.md` and `docs/decisions/`: layers and ADRs. `.ai/`: check baselines and metrics.

## Commands

```sh
scripts/check.sh                                   # the one check; run before handing back
swift build -c release -Xswiftc -warnings-as-errors --scratch-path .build-check
scripts/test.sh --scratch-path .build-check-test   # Swift tests (passes Swift Testing paths for CLT)
node --test Tests/vault.test.mjs                   # vault tests
node scripts/vault.mjs check                       # fails if plaintext or the key is tracked
scripts/build-app.sh                               # build/MenubarWindows.app, ad-hoc signed
scripts/make-dmg.sh                                # dmg from the built app
scripts/release.sh                                 # app + dmg + cask version and sha256; offline
scripts/capture-screenshots.sh                     # demo-mode screenshots, see the skill
scripts/audit.sh                                   # writes .ai/metrics.json
git config core.hooksPath scripts/hooks            # once per clone
```

If a copy of the app may be running from `.build/release`, never build into `.build/release`; always pass
`--scratch-path .build-check`. `build-app.sh` and `release.sh` build into `.build/` and rewrite `build/`.

## Conventions

- New pure logic goes in Core with tests. App code stays thin around AppKit, SwiftUI and AX.
- Every Swift file starts with a header comment: what it does, then "Gotchas:". Keep it current.
- Swift 5 language mode on purpose (see `Package.swift`). Zero warnings.
- Settings keys are prefixed `mw.` and typed in `Sources/MenubarWindows/Settings.swift`.
- The name, bundle id and tagline live only in `Sources/MenubarWindows/AppInfo.swift`.

## DO NOT

- Add a dependency (Swift package, npm package, brew formula) without asking.
- Add a top-level folder or file without updating `.ai/structure.txt` and asking.
- Edit tests, baselines, check scripts, CI or `Package.swift` flags to make a check pass. Fix the code.
- Add `try!`, `as!`, `unsafeBitCast`, `@unchecked Sendable`, `nonisolated(unsafe)`, `@preconcurrency`,
  force unwraps or lint suppressions. The ratchet in `.ai/baseline.json` only goes down.
- Import AppKit, SwiftUI, ApplicationServices, Combine or Cocoa in `Sources/MenubarWindowsCore/`.
- Write a helper before searching for an existing one (`grep -rn` in `Sources/`).
- Print, log or commit secrets, `.vault-key`, `MWVAULT_KEY` or anything in `private/`.
- Hand-edit the `private.enc` folder (use `node scripts/vault.mjs encrypt`), `Resources/` (use
  `scripts/make-icon.sh`) or `assets/screenshots/` (use `scripts/capture-screenshots.sh`).
- Take screenshots of the real desktop. Demo mode is the only safe way: it never shows real apps.
- Quit or restart a running MenubarWindows, or change macOS system settings.

## Gotchas that cost time

- Panel level is `.popUpMenu` and `constrainFrameRect` returns the rect unchanged; without it AppKit
  pushes the panel below the menu bar (`Sources/MenubarWindows/StripPanel.swift`).
- The content layer has a 0.01-alpha fill. Fully transparent pixels let clicks fall through.
- The panel extends `topOverscan` (6pt) above the screen edge so top-row clicks land on a tab.
- Cocoa is bottom-left origin; AX and CGWindowList are top-left. Convert with
  `MenuBarGeometry.cocoaRect(fromTopLeft:)`.
- Raising needs `AXFrontmost` on the app element plus activating the app; AXRaise alone is unreliable.
  Un-minimize before AXRaise (`Sources/MenubarWindows/WindowRaiser.swift`).
- Notch: on notched screens the strip ends at `auxiliaryTopLeftArea`; too little room hides it.
- Status icons are level-25 windows in the bar band; the region's right edge stays clear of them.
- Never sort tabs by CG z-order: it changes on every click. Ordering lives in Core `TabOrdering`.
- AX calls are main-thread IPC with a 0.2s timeout set on every element, not inherited from the app.
- `scripts/test.sh` exists because the Command Line Tools do not find Swift Testing on their own.
- `scripts/app-info.sh` reads `AppInfo.swift` with sed: keep each `static let x = "value"` on one line.
- Settings for `swift run` and the .app live in different defaults domains.
