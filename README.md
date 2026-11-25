# MenubarWindows

Your windows, as tabs in the empty middle of the menu bar.

MenubarWindows is a small, free macOS app (private beta) that draws a strip of window tabs **inside the
menu bar**, one tab per window on that display. Click a tab to bring its window forward. The tabs reach
the very top edge of the screen, so you can push the pointer up and click without aiming.

The product name, bundle identifier and tagline live in one place:
[`Sources/MenubarWindows/AppInfo.swift`](Sources/MenubarWindows/AppInfo.swift). The scripts read them
from there (`scripts/app-info.sh`), and the version comes from [`VERSION`](VERSION).

## Features

- Tabs live in the unused middle of the menu bar, left of the status icons, on every display that shows
  a menu bar.
- Handles the notch: on notched screens the strip ends just left of it.
- Clicks land at the very top pixel row: the panel extends 6pt above the screen edge.
- Stays clear of status icons, and leaves the Apple menu and the app name usable.
- Five tab orders, pinning, four label modes, two tab styles, accent color, width and alignment.
- Per-display on/off, hide on demand, hide in full screen, hide when only one window is open.
- Right-click a tab: hide for a few seconds, pin or unpin its app, close or minimize the window,
  Settings, Quit. Middle-click a tab to close its window.
- Light on resources: two timers (0.5s and 2s) and no background work beyond that.
- No network access, no analytics. Nothing leaves your Mac.

## Settings

Open Settings by right-clicking any tab and choosing **Settings…**, or by opening the app again from
Finder or Spotlight (there is no Dock icon and no menu bar icon by design). Every change applies at once.

| Section | Options (default in bold) |
| --- | --- |
| Appearance | Tab style: **Square, flush with the top** or Rounded. Color theme: **Match the system** or Pure black. Tab height: 50 to 100% of the menu bar (**85%**). Active tab: Underline, **Brighter fill**, Both. Accent: **system** or a custom color. Width: **Automatic (fit the tabs, up to a maximum)** or Fixed, 240 to 900pt (**560**). Alignment: **Center** or Left. Placement: **Middle of the menu bar** or Top left, right after the Apple menu. Cover the app's menu titles: **on by default**; a filler bar joins the tabs and hides the titles (right-click a tab, Hide for 10 seconds, to use a menu). Live preview. |
| Tabs and order | Order (see below, **Automatic**). Pinned apps list. Labels: App name, Window title, **App name and title**, Icon only. **Shrink to icon-only when crowded**. Show up to 3 to 12 tabs (**8**); the rest go in a **+N** tab that opens a menu. Live preview. |
| Displays | **Show on all displays**, or a toggle per connected display (stored by display UUID). |
| Behaviour | Hide when only one window is open (off). **Hide in full-screen apps**. Include minimized windows (off). **Ignore small helper windows** smaller than **100pt** (also drops windows the app marks with a non-standard AX subrole, such as Edge's Find bar). Hide-for durations (**10, 30, 60** seconds). |
| General | Launch at login (SMAppService; only from the .app bundle). **Show Settings when the app is opened again**. Accessibility status and setup guide. |
| About | Version, tagline, privacy note, Reset to defaults. |

### Tab order modes

1. **Automatic**: a stable first-seen order. A new window gets the last tab. Clicking never reshuffles.
2. **Most recently used first**: the window you used last comes first.
3. **App name A to Z**: by app name; windows of one app keep their automatic order.
4. **Left to right on screen**: by each window's left edge, higher windows first on a tie.
5. **Pinned apps first, then automatic**: pinned apps in pin order, then everything else.
   Pin from a tab's right-click menu. Pinning while in another mode switches to this one.

Ordering is a pure function in `Sources/MenubarWindowsCore/TabOrdering.swift` with unit tests.

## Build and run

Requirements: macOS 13 or later, Swift 6 toolchain (Command Line Tools are enough). No third-party
dependencies, and nothing is downloaded at build time.

```sh
swift run -c release              # quick run; Accessibility is granted to your terminal
./scripts/test.sh                 # unit tests (Swift Testing), offline
./scripts/build-app.sh            # build/MenubarWindows.app, ad-hoc signed
./scripts/make-dmg.sh             # build/MenubarWindows-<version>.dmg with an Applications shortcut
./scripts/make-icon.sh            # only when the icon design changes; output is committed in Resources/
```

`scripts/test.sh` exists because, with only the Command Line Tools selected, SwiftPM does not find the
bundled Swift Testing framework by itself; the script passes its paths. With Xcode selected, plain
`swift test` works too.

Headless check (no UI), for the bare binary or the bundle:

```sh
.build/release/MenubarWindows --list
build/MenubarWindows.app/Contents/MacOS/MenubarWindows --list
```

It prints the active tab order and filters, and per screen the strip region and the windows in tab
order. Any setting can be overridden for one run with a launch argument, for example
`-mw.order recentFirst` or `-mw.hasCompletedOnboarding YES`.

The bare binary and the bundle keep separate settings: the defaults domain is the executable name for
`swift run` and the bundle identifier for the app.

## Permissions

The app reads window titles, focus and positions through the **Accessibility** API. It does **not** use
Screen Recording.

On first launch, and whenever access is missing, a short guide explains what the app does and why it
needs access, opens **System Settings → Privacy & Security → Accessibility**, and shows a live status that
flips to granted by itself. If you close the guide, a **Grant Accessibility access** tab stays in the menu
bar; click it to reopen the guide.

For `swift run`, macOS grants access to the terminal app, and everything run from that terminal gets it
too. Use a binary you trust.

## Privacy

MenubarWindows makes no network connections, has no analytics, no crash reporting and no update check.
Window titles are read in memory to draw tabs and are never stored or sent anywhere. Settings are stored
in the app's own `UserDefaults`.

## Known limits

- **Not sandboxable, so not on the App Store.** It needs the Accessibility API and the private
  `_AXUIElementGetWindow` (to map AX windows to CG window IDs without Screen Recording). If that symbol
  stops working, matching falls back to window bounds within 2pt.
- **Menu bar auto-hide:** when the system reserves no menu bar and no app menu titles are seen on a
  display, that display gets no strip.
- **Full screen:** detection is a best-effort check of `AXFullScreen` on the frontmost window.
- **Notch:** the strip is limited to the area left of the notch. If too little room is left, it hides.
- **The strip may cover the frontmost app's menu titles** in the middle of the bar. Right-click a tab and
  use **Hide for …** to reach them.
- **Empty strip space is not click-through.** In Automatic width the strip is trimmed to the tabs, so this
  only matters with a fixed width.
- **Windows on other Spaces** do not get a tab (they are not on screen), but they keep their slot in the
  automatic order when they come back.
- **Include minimized windows** asks every regular app for its windows on each refresh, which costs a
  little more.
- Not verified interactively for every option: see CHANGELOG for what was checked.

## Release checklist (not done yet)

The beta build is ad-hoc signed, which only runs without warnings on the Mac that built it. Distribution
to other Macs needs an Apple Developer ID certificate and notarization. These commands are documented
here and were **not** run:

```sh
# 1. Sign with hardened runtime and a Developer ID Application certificate.
codesign --force --deep --options runtime --timestamp \
  --sign "Developer ID Application: <Name> (<TEAMID>)" build/MenubarWindows.app
codesign --verify --deep --strict --verbose=2 build/MenubarWindows.app

# 2. Build the dmg, sign it, and submit it for notarization.
./scripts/make-dmg.sh
codesign --sign "Developer ID Application: <Name> (<TEAMID>)" --timestamp build/MenubarWindows-<version>.dmg
xcrun notarytool submit build/MenubarWindows-<version>.dmg \
  --keychain-profile "<notary-profile>" --wait

# 3. Staple the ticket and check Gatekeeper.
xcrun stapler staple build/MenubarWindows-<version>.dmg
spctl --assess --type open --context context:primary-signature -v build/MenubarWindows-<version>.dmg
```

Also before a public release: bump `VERSION`, update `CHANGELOG.md`, replace the placeholder `LICENSE`,
and fill in the waitlist link on the site.

## Project layout

```
Package.swift
VERSION                          app version (read by build-app.sh)
Resources/                       AppIcon.icns, AppIcon-1024.png (generated, committed)
Sources/MenubarWindowsCore/
  TabOrdering.swift              order modes, ordering function, first-seen and MRU tracker
  TabLabel.swift                 label modes and label text
Sources/MenubarWindows/
  AppInfo.swift                  display name, bundle id, tagline (single source)
  main.swift                     entry point, --list
  AppDelegate.swift              panels per screen, refresh loop, permission poll, tab actions
  Settings.swift                 typed UserDefaults settings, live change publisher, display ids
  SettingsView.swift             SwiftUI Settings window
  StripPreview.swift             live preview built from the real strip and pill views
  OnboardingView.swift           three-step first-launch and permission guide
  WindowControllers.swift        NSWindow hosting, Launch at login, Accessibility request
  StripPanel.swift               the panel and strip view (layout, scroll, menus, +N tab)
  PillView.swift                 one tab (icon, label, style, active indicator, clicks)
  MenuBarGeometry.swift          strip region, notch, status icons, coordinate conversion
  WindowProvider.swift           CG window list merged with AX titles, focus and filters
  WindowRaiser.swift             raise, close and minimize through AX
  AccessibilityHelpers.swift     AX wrappers and _AXUIElementGetWindow
  ListCommand.swift              --list output
Tests/MenubarWindowsCoreTests/   ordering and label tests
scripts/                         app-info.sh, build-app.sh, make-dmg.sh, make-icon.sh(+.swift), test.sh
site/                            private-beta landing page (static, offline)
```
