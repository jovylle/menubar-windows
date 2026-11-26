# 0003. Distribute as a Homebrew cask and a dmg

Date: 2026-11-26 (records the existing design). Status: accepted, not published yet.

## Context
The app is a `.app` that cannot go on the App Store (0001). Users want a one-line install.

## Decision
Ship a dmg on GitHub releases and a cask in `jovylle/homebrew-tap`
(`brew install --cask jovylle/tap/menubarwindows`). The cask source lives in
`packaging/homebrew/Casks/menubarwindows.rb`; `scripts/release.sh` rewrites its version and sha256
offline. Publishing (signing, notarizing, uploading, pushing the tap) stays manual.

## Consequences
- Needs a Developer ID certificate and notarization; no `xattr` quarantine workaround in the cask.
- The release asset must be publicly downloadable.
