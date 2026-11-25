# Changelog

## 0.1.0 (private beta, unreleased)

First productized build of the menu bar window switcher.

### Added
- Settings window (Appearance, Tabs and order, Displays, Behaviour, General, About) with a live preview
  drawn by the real tab views. Every setting applies immediately.
- Five tab orders: Automatic (stable first-seen), Most recently used first, App name A to Z, Left to
  right on screen, Pinned apps first. Pin or unpin an app from a tab's right-click menu.
- Label modes (app name, window title, both, icon only) and shrink to icon-only when crowded.
- Square or rounded tabs, underline or brighter-fill active indicator, system or custom accent color.
- Automatic strip width that fits the tabs (so the rest of the menu bar stays clickable), or a fixed
  width; center or left alignment.
- Max tabs with a trailing +N tab that opens a menu of the remaining windows.
- Per-display toggles, hide when only one window is open, include minimized windows, ignore small helper
  windows (fixes Edge's Find bar showing as a tab), editable hide-for durations.
- Right-click: Close window, Minimize window, Settings. Middle-click closes a window.
- Launch at login (SMAppService) and opening Settings when the app is opened again.
- Three-step onboarding with a live Accessibility status; the grant pill remains as a fallback.
- App bundle, ad-hoc signing, icon generator and dmg scripts. Unit tests for ordering and labels.
- `--list` prints the active order mode and lists windows in tab order.

### Changed
- Tabs no longer sort by app name then window ID; Automatic keeps first-seen order instead.

### Verified in this build
- `swift build -c release` with no warnings; 15 unit tests pass; the bundle passes `codesign --verify`;
  the bundle binary runs `--list`, and a short launch put one strip panel per display at the pop-up
  menu level, 6pt above the top edge, with a screenshot showing the tabs.
- Not clicked through by hand: the Settings and onboarding windows, the context menu items, the +N
  menu, Launch at login and the custom accent picker.
