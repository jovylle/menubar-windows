# 0006. The strip owns the space between the Apple menu and the notch

Date: 2026-11-27. Status: accepted.

## Context
On a notched screen the old strip was a fixed-width block against the notch, with an optional
"Top left" placement. Few tabs left a gap, and the two settings (placement and alignment) overlapped.

## Decision
- On a notched screen the region is everything between the Apple menu (`appleMenuInset`) and the notch.
  The "Maximum width" setting does not limit it there. Other screens keep the configured width.
- Three or more window tabs fill the whole region, and equal-width tabs ignore the widest-tab cap
  (`StripFill` in Core). With fewer tabs, alignment places them.
- Alignment on a notched screen is Left (hugs the Apple menu) or Middle (against the notch). Elsewhere it is
  Left, Middle or Right. The Placement setting is removed. A stored `left` on a notched screen shows as Left;
  the stored value is kept.
- The picker's labels come from one fact: whether any connected screen has a notch. When it does, the picker
  shows Left and Middle for every screen. Then a screen without a notch treats the stored `center` (and `left`)
  as Left, the Left span right after the Apple menu, and the stored `right` as Middle, a centered block. The
  mapping is `StripPlacement.placement` in Core, and the strip, the preview and `--list` all use it.
- "Cover the Apple menu" (off by default) starts the strip at the screen edge instead of after the Apple
  menu. It applies to Left on any screen and to the region's left edge on a notched screen, so the top-left
  corner selects the first tab.

## Consequences
- The Apple menu is hidden under the first tab when the cover option is on; "Hide for ..." reveals it.
- Off a notch, Left puts the tabs right after the Apple menu (`StripPlacement.leftSpan`), clipped only by the
  status icons. Middle and Right stay centered or at the end.
- Before this rule, the picker's labels were global but the placement was per screen. With a notched laptop and
  an external display, a stored `center` showed "Left" but the external screen centered the tabs, so Left did
  nothing there. Now Left starts after the Apple menu on that screen too.
- Code: `Sources/MenubarWindowsCore/StripFill.swift`, `Sources/MenubarWindowsCore/StripPlacement.swift`,
  `Sources/MenubarWindows/MenuBarGeometry.swift`.
