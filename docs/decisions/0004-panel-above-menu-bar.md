# 0004. Tabs live in a panel above the menu bar

Date: 2026-11-26 (records the existing design). Status: accepted.

## Context
macOS has no API to draw inside the menu bar except status items, which sit on the right and are
too small for window tabs.

## Decision
One borderless, non-activating `NSPanel` per screen at level `.popUpMenu`, which is above the menu bar
(`.mainMenu`) and its status items. `constrainFrameRect` returns the rect unchanged, because AppKit
otherwise pushes the panel below the menu bar. The panel extends `topOverscan` (6pt) above the screen
edge, and its content layer has a 0.01-alpha fill so clicks on near-transparent pixels do not fall
through. `canBecomeKey` is false, so clicking a tab never steals focus. The region avoids the Apple
menu, the app name, status icons (level-25 windows) and the notch.

## Consequences
- The strip can cover the frontmost app's menu titles; "Hide for ..." reveals them.
- Empty strip space is not click-through; Automatic width trims the panel to the tabs.
- Code: `Sources/MenubarWindows/StripPanel.swift`, `Sources/MenubarWindows/MenuBarGeometry.swift`.
