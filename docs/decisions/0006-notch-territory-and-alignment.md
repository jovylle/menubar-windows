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
- Alignment is Middle or Right only. The Placement setting is removed. A stored `left` falls back to Middle.
- "Cover the Apple menu" (off by default, notched screens only) starts the region at the screen edge,
  so the top-left corner selects the first tab.

## Consequences
- The Apple menu is hidden under the first tab when the cover option is on; "Hide for ..." reveals it.
- The top-left placement is gone on screens without a notch.
- Code: `Sources/MenubarWindowsCore/StripFill.swift`, `Sources/MenubarWindows/MenuBarGeometry.swift`.
