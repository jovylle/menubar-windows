# Landing page

A single static page. Nothing is hosted yet.

## Preview locally

Open `index.html` in a browser. It works from `file://`: no JavaScript framework, no CDN, no remote
fonts, images or scripts. The assets are `assets/icon.png` and four screenshots copied from
`../assets/screenshots/` (`hero.png`, `hero-black.png`, `settings-tabs.png`, `strip-compact.png`).
`scripts/capture-screenshots.sh` copies them here again after each capture.

## Before it goes public

- Add a real download link only after the app is signed with a Developer ID certificate and notarized.
- Pick the final product name, then update the name in `Sources/MenubarWindows/AppInfo.swift`
  and in this page.
- Add hosting and a domain.
