// main.swift
// Entry point. `--list` prints the active settings, the detected strip region and the window list per
// screen, then exits without starting the UI.
//
// Gotcha: the accessory activation policy hides the Dock icon and the app menu. Accessibility
// permission belongs to whatever macOS sees as the app: the .app bundle when built with
// scripts/build-app.sh, or the terminal when run with `swift run`.

import AppKit

if CommandLine.arguments.contains("--list") {
    ListCommand.run()
    exit(0)
}

let application = NSApplication.shared
application.setActivationPolicy(.accessory)
let appDelegate = AppDelegate()
application.delegate = appDelegate
application.run()
