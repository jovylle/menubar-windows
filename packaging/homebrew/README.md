# Homebrew

MenubarWindows is a `.app`, so the right package type is a **cask**, not a formula. Users will run:

```
brew install --cask jovylle/tap/menubarwindows
```

`jovylle/tap` means the GitHub repo `jovylle/homebrew-tap`. Homebrew maps the short name `tap` to
`homebrew-tap` on its own.

Nothing here is published yet. The repo is private, and Homebrew needs a public download URL.

## One-time setup (maker, when the product goes public)

1. Make the release asset public: a GitHub release `v<version>` on `jovylle/menubar-windows` with
   `MenubarWindows-<version>.dmg` attached. A private repo's release assets cannot be downloaded
   by `brew` without a token, so the repo or at least the release must be public.
2. Create the public repo `jovylle/homebrew-tap` with a `Casks/` folder.
3. Sign with a Developer ID certificate and notarize the app. A cask installs the app with the
   download quarantine flag. Without notarization, macOS refuses to open it on first launch.
   Do not add an `xattr` workaround to the cask. Homebrew's maintainers reject that for casks
   submitted to the main repository, and it hides a real warning from users.

## Each release

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
