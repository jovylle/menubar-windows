# 0007. Betas publish from main; live is a promoted beta

Date: 2026-11-27. Status: accepted.

## Context
Releases were manual (`scripts/release.sh`, upload, copy the cask). The user wants every merge to `main`
available as a beta, and a deliberate step to make a tested beta live.

## Decision
- After `check` passes on `main`, `beta.yml` builds one dmg, publishes it as pre-release
  `v<VERSION>-beta.<run>` and updates the tap cask `menubarwindows@beta`.
- `promote.yml` (manual) takes a beta tag, checks the sha256, re-publishes the same dmg as `v<VERSION>`
  and updates the tap cask `menubarwindows`. Nothing is rebuilt, so live is exactly what was tested.
- The beta number goes in `CFBundleVersion` only (`BUILD_NUMBER` in `scripts/build-app.sh`). The app
  reports `VERSION`, so the promoted bytes need no change.
- The tap is written with the fine-grained secret `TAP_TOKEN` (Contents write on the tap repo only).

## Consequences
- Builds stay ad-hoc signed and not notarized; macOS may ask for Accessibility again after an update.
- `VERSION` must be bumped before the first beta of a new release.
- The cask files in `packaging/homebrew/Casks/` are templates; the tap holds the current values.
