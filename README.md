# MenubarWindows

A small macOS accessory app that draws a strip of window pills **inside the menu bar**, in the empty
space between the frontmost app's menu titles (File, Edit, View, ...) and the status icons on the right.
Each pill is one open window on that screen. The focused window's pill is highlighted. Clicking a pill
raises that window and activates its app.

It is meant for 2 to 5 windows per monitor. Pills shrink to fit, and a wider set scrolls horizontally
with the trackpad or mouse wheel.

## Requirements

- macOS 13 or later
- Swift 6.3 toolchain (Xcode command line tools)
- No third-party dependencies, no network access

## Run it

```sh
swift run -c release
```

Or build once and run the binary:

```sh
swift build -c release
.build/release/MenubarWindows
```

Quit: right-click anywhere on the strip and choose **Quit MenubarWindows**. There is no Dock icon and
no status item.

Check geometry without starting the UI:

```sh
.build/release/MenubarWindows --list
```

This prints, per screen, the detected free strip frame and the window list (app, title, focused flag).

## Grant Accessibility permission

The app reads window titles, focus, and positions through the Accessibility API. It does **not** use
Screen Recording, so it never needs that permission.

On first launch macOS asks for Accessibility access. If you miss the prompt:

1. Open **System Settings → Privacy & Security → Accessibility**.
2. Enable the app that runs the binary. For `swift run`, that is your terminal (Terminal, iTerm, Ghostty,
   and so on). For a built binary, add `.build/release/MenubarWindows` with the **+** button.
3. Restart the app. Until access is granted, the strip shows one pill, **Grant Accessibility access**,
   which opens that settings pane. The app rechecks permission every 2 seconds.

Granting access to the terminal also grants it to anything run from that terminal, so use a binary you
trust.

## How it works

- One non-activating `NSPanel` per screen, at status-bar level, with the height of that screen's menu bar.
- The strip is anchored to the middle of the bar, `StripLayout.stripWidth` (560pt) wide. On notched
  screens it ends 12pt left of the notch instead. The frontmost app's `AXMenuBar` item positions only
  push its left edge in, when an app has so many menus that they reach the strip.
- Windows come from `CGWindowListCopyWindowInfo`, filtered to layer 0, alpha > 0, and size > 80x40. Each
  window is then matched to an AX window, which supplies its title and focus.
- Refresh: strip geometry every 1s and on app activation, window list every 0.5s, permission every 2s.

## Known limits

- **Not sandboxable, so not App Store.** It uses the Accessibility API and private `_AXUIElementGetWindow`.
- **Menu bar auto-hide:** when the system reserves no menu bar height, the strip hides.
- **Full-screen apps:** when the frontmost window is full screen, the strip hides. This is a best-effort
  check of `AXFullScreen`.
- **Notch:** the strip is limited to the area left of the notch. On a narrow notch display the free space
  can be too small, and the strip hides.
- **Multiple displays:** the menu bar belongs to one display (the one with the menu bar). Other displays
  have no reserved menu bar height, so no strip is drawn there. Use `--list` to see what is detected.
- **Empty strip area is not click-through.** Clicks on empty space inside the strip do nothing and do not
  reach the menu bar underneath.
- Pill order is by app name, then window ID, so pills do not reorder when you click. The order is not
  the window stacking order.
- Window matching relies on the private `_AXUIElementGetWindow`. If it stops working in a future macOS,
  matching falls back to bounds within 2pt.
- Not tested interactively in this build: only `swift build` and `--list` were run.

## Layout

```
Package.swift
Sources/MenubarWindows/
  main.swift                 entry point, --list
  AppDelegate.swift          panels per screen, timers, permission poll
  StripPanel.swift           NSPanel and the strip content view (layout, scroll, right-click menu)
  PillView.swift             one pill (icon, title, active highlight, click)
  MenuBarGeometry.swift      free strip computation, AX to Cocoa coordinates
  WindowProvider.swift       CG window list merged with AX titles and focus
  WindowRaiser.swift         AXRaise and app activation
  AccessibilityHelpers.swift AX wrappers and _AXUIElementGetWindow
  ListCommand.swift          --list output
```
