---
name: capture-demo-screenshots
description: Capture or refresh the MenubarWindows screenshots (assets/screenshots/ and site/assets/) from the real app in demo mode, then privacy-review every PNG. Use only in the menubar-windows repo, when a UI change needs new screenshots, a README or site image is outdated, or someone asks for a screenshot of the strip, a menu, Settings or onboarding.
---

# Capture demo screenshots (MenubarWindows)

Screenshots in this repo come only from demo mode. Never capture the real desktop, a real strip or
real Settings: they show the user's own apps, window titles and display names.

## Demo mode flags

Launch arguments for one run (see `Sources/MenubarWindows/DemoMode.swift`):

| Flag | Effect |
| --- | --- |
| `-mw.demo YES` | Invented windows and apps (`Sources/MenubarWindowsCore/DemoData.swift`), invented displays, permission shown as granted, throwaway settings suite |
| `-mw.demoCount <1...8>` | Number of fake windows (default 6) |
| `-mw.demoActive <index>` | Focused fake tab, 0-based (default 1) |
| `-mw.demoMenu <index>` | Opens that tab's right-click menu about a second after launch |
| `-mw.demoBackdrop YES` | Dark blue backdrop window behind the strip, so the real menu bar is covered |
| `-mw.openSettings YES` | Opens Settings at launch |
| `-mw.settingsPane <name>` | `appearance`, `tabs`, `displays`, `behaviour`, `general` or `about` |
| `-mw.showOnboarding YES` | Opens the first-run guide |
| `-mw.debugAppearance light` | Forces light or dark for one run, without changing system settings |

Any other `-mw.<key>` setting applies too, for example `-mw.colorTheme black`.

## Steps

1. Build the release binary. If a copy of the app may be running from `.build/release`, ask first, or
   build elsewhere and point the script at it:
   ```sh
   swift build -c release --scratch-path .build-shots
   MW_BINARY=.build-shots/release/MenubarWindows ./scripts/capture-screenshots.sh
   ```
   Otherwise: `swift build -c release && ./scripts/capture-screenshots.sh`.
2. To retake only some shots, name them: `./scripts/capture-screenshots.sh context-menu.png settings-tabs.png`.
3. Do not click or type while it runs (about a minute). A click closes the demo menu or keeps Settings
   inactive. The script retries and lists shots that stayed inactive. Re-run with those names.
4. The script captures only the launched process's own windows (`screencapture -l <id> -o`), composes
   `hero.png` and `hero-black.png` with `scripts/screenshot-tool.swift`, and copies four images to
   `site/assets/`.

## Privacy review (required for every PNG)

Open every new or changed PNG and check, before staging it:

- Only invented names show: Draftpad, Shellbox, Mockups, Planner, Pagefold, Statline, Tunebox, Inkwell.
- No real app, window title, file name, user name, display name, wallpaper or notification.
- Settings, Displays shows invented display names only. About shows the version, nothing personal.
- The real menu bar is covered by the demo backdrop in strip shots.

List the reviewed files in the PR and tick "screenshots reviewed". If one fails review, delete it and
retake it. Never edit a screenshot by hand.

## Gotchas

- `.build/screenshot-offset-*` and `.build/screenshot-tool` are written by the script. A custom
  `--scratch-path` build does not move them.
- The strip capture keeps its full height: the top 6pt are the click overscan.
- New UI that shows any name in demo mode must take it from `DemoData.swift`.
