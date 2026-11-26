# 0005. Demo mode for screenshots

Date: 2026-11-26 (records the existing design). Status: accepted.

## Context
Screenshots of the real app show the user's own apps, window titles and display names, and would be
committed to a public repo.

## Decision
`-mw.demo YES` swaps the window source for invented windows, apps and displays from
`Sources/MenubarWindowsCore/DemoData.swift`, with icons drawn in code and a settings suite wiped at
every demo launch. `scripts/capture-screenshots.sh` launches the binary once per shot and captures
only that process's windows by window ID. Every PNG is reviewed before it is committed (project skill
`capture-demo-screenshots`).

## Consequences
- Demo mode is the only allowed way to make screenshots. Anything shown in demo mode must come from
  `DemoData.swift`.
- Close, minimize and middle-click are no-ops on fake tabs; no AX or CG call is made for them.
