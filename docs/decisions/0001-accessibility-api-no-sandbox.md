# 0001. Accessibility API, no sandbox, no App Store

Date: 2026-11-26 (records the existing design). Status: accepted.

## Context
The app needs every window's title, focus, position and a way to raise, close and minimize it.
CGWindowList gives IDs and bounds, but titles from it need Screen Recording permission.

## Decision
Read titles and focus, and act on windows, through the Accessibility (AX) API. Map AX windows to
CGWindowIDs with the private `_AXUIElementGetWindow`, falling back to matching bounds within 2pt.
Ask for Accessibility only, never Screen Recording. Ship outside the sandbox.

## Consequences
- The app cannot be sandboxed, so it cannot ship on the Mac App Store. Distribution is a signed,
  notarized dmg and a Homebrew cask (0003).
- AX calls are synchronous IPC; every element gets a 0.2s messaging timeout.
- If the private symbol stops working, bounds matching keeps the app usable.
