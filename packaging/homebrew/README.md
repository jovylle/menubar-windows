# Homebrew

MenubarWindows is a `.app`, so the right package type is a **cask**, not a formula. Users will run:

```
brew install --cask jovylle/tap/menubarwindows
```

`jovylle/tap` means the GitHub repo `jovylle/homebrew-tap`. Homebrew maps the short name `tap` to
`homebrew-tap` on its own.

The tap is published at https://github.com/jovylle/homebrew-tap and the 0.1.0 release carries the dmg.
The cask in this folder is the source of truth: copy it into the tap repo for each release.

## One-time setup (maker, when the product goes public)

1. Make the release asset public: a GitHub release `v<version>` on `jovylle/menubar-windows` with
   `MenubarWindows-<version>.dmg` attached. A private repo's release assets cannot be downloaded
   by `brew` without a token, so the repo or at least the release must be public.
2. Create the public repo `jovylle/homebrew-tap` with a `Casks/` folder.
3. Sign with a Developer ID certificate and notarize the app. A cask installs the app with the
   download quarantine flag. Without notarization, macOS refuses to open it on first launch.
   Do not add an `xattr` workaround to the cask. Homebrew's maintainers reject that for casks
   submitted to the main repository, and it hides a real warning from users.

## Beta channel and promotion

Every green `check` on `main` runs `.github/workflows/beta.yml`. It builds the dmg once, publishes it as
the GitHub pre-release `v<VERSION>-beta.<run>` and updates `menubarwindows@beta` in the tap:

```
brew install --cask jovylle/tap/menubarwindows@beta
brew upgrade --cask menubarwindows@beta
```

To go live, run the `promote` workflow (Actions tab) with a beta tag, for example `v0.1.1-beta.7`. It
re-publishes that same dmg as `v0.1.1` and updates the live cask. Nothing is rebuilt.

- Bump `VERSION` when you start the next release. The beta number comes from the workflow run.
- Both workflows need the repo secret `TAP_TOKEN`: a fine-grained token with Contents read and write on
  `jovylle/homebrew-tap` only.
- The cask files in this folder are templates. The workflows rewrite `version` and `sha256` and push
  to the tap, which holds the current versions.

## Each release (manual, without the workflows)

```
scripts/release.sh            # builds the app and dmg, rewrites version and sha256 in the cask
```

Then upload the dmg to the GitHub release, copy `Casks/menubarwindows.rb` into the tap repo, commit
and push. Users get the new version with `brew upgrade --cask menubarwindows`.

## Check the cask before pushing

```
brew style packaging/homebrew/Casks/menubarwindows.rb
brew audit --cask --new jovylle/tap/menubarwindows
```

Both need network access and install Homebrew's linting gems on first use, so run them on a
machine where that is allowed.

## Installing without Homebrew

- Download the dmg from the release and drag the app to Applications.
- Or build from source: `swift build -c release`, then `scripts/build-app.sh`.

## Later: the main Homebrew cask repository

Homebrew/homebrew-cask accepts apps that are notarized, have a stable public download URL and
some notability (users, stars). Submit there once the product has been public for a while. The
file in this folder is already in the shape that repo expects.
