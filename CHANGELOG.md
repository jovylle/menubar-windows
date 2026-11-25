# Changelog

## 0.1.0 (unreleased)

First productized build of the menu bar window switcher.

### Added
- Settings window (Appearance, Tabs and order, Displays, Behaviour, General, About) with a live preview
  drawn by the real tab views. Every setting applies immediately.
- Five tab orders: Automatic (stable first-seen), Most recently used first, App name A to Z, Left to
  right on screen, Pinned apps first. Pin or unpin an app from a tab's right-click menu.
- Label modes (app name, window title, both, icon only) and shrink to icon-only when crowded.
- Square or rounded tabs, underline or brighter-fill active indicator, system or custom accent color.
- Color theme: match the system (light or dark) or Pure black. Tab height, 50 to 100% of the menu bar.
- Placement: middle of the menu bar, or top left right after the Apple menu.
- Automatic strip width that fits the tabs (so the rest of the menu bar stays clickable), or a fixed
  width; center or left alignment.
- Max tabs with a trailing +N tab that opens a menu of the remaining windows.
- Per-display toggles, hide when only one window is open, include minimized windows, ignore small helper
  windows (fixes Edge's Find bar showing as a tab), editable hide-for durations.
- Right-click: Close window, Minimize window, Settings. Middle-click closes a window.
- Launch at login (SMAppService) and opening Settings when the app is opened again.
- Three-step onboarding with a live Accessibility status; the grant pill remains as a fallback.
- App bundle, ad-hoc signing, icon generator and dmg scripts. Unit tests for ordering and labels.
- `--list` prints the active settings (including placement and tab height) and lists windows in tab
  order. `--version` prints the version.

- Demo mode for screenshots and videos (`-mw.demo YES`, with `-mw.demoCount`, `-mw.demoActive`,
  `-mw.demoMenu`, `-mw.demoBackdrop`): invented windows, drawn icons and invented display names, in a
  throwaway settings suite. `-mw.openSettings`, `-mw.settingsPane` and `-mw.showOnboarding` open those
  windows at launch.
- `scripts/capture-screenshots.sh` captures the app's own windows only, and `assets/screenshots/` holds
  the results. The landing page and README show them.

### Changed
- Tabs no longer sort by app name then window ID; Automatic keeps first-seen order instead.

### Fixed
- Tab labels no longer truncate when the tab is at its natural width: the width now includes the 4pt
  that NSTextField pads around its text.
- The focused window's tab often did not show as active. The app's focused window can be a helper
  window with no tab (Edge's Find bar, a popover); the main window is used then. Windows matched by
  bounds are matched by AX element too, and an AX timeout keeps the previous active tab.
- Hide in full-screen apps also works while a helper window has focus over the full-screen window.
- Minimized tabs dimmed their label to about 2.6:1 contrast. Only the icon is dimmed now; every label
  is at least 4.5:1 in light, dark and Pure black.
- The AX messaging timeout (0.2s) now covers window and menu elements, not only app elements, so a
  hung app cannot stall the strip for the 6s system default per call.
- Middle-click close refreshes the strip right away, as the context menu item does.
- Settings: corrected help text for Tab style, Active tab, Placement and minimized windows. Alignment
  is disabled with Top left placement, which now always starts the tabs at the left (also in Fixed
  width). The preview follows the placement.
- Settings and onboarding windows are released when closed, which stops their permission timers.

### Verified in this build
- `swift build -c release` with no warnings; 31 unit tests pass (`scripts/test.sh`).
- Clean `scripts/build-app.sh` and `scripts/make-dmg.sh`: `codesign --verify --deep --strict` passes,
  Info.plist has LSUIElement, LSMinimumSystemVersion 13.0 and the version from VERSION, the icon is in
  the bundle, the dmg mounts read-only with the app and an Applications link. The bundle binary runs
  `--version` and `--list` and exits 0.
- With two displays, the active tab showed on the external display (read back through the strip's own
  VoiceOver labels). Light, forced dark and Pure black strips were screenshotted; measured label
  contrast 13.5:1 to 21:1.
- Idle CPU: 0.7% on average over 20 seconds with four windows.
- Not clicked through by hand: the Settings and onboarding windows, the context menu items, the +N
  menu, Hide for, Launch at login, the custom accent picker, and display connect or disconnect.
