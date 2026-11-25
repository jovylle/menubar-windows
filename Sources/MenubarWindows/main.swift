// main.swift
// Entry point. `--list` prints the detected free strip and window list per screen, then exits
// without starting the UI.
//
// Gotcha: the accessory activation policy hides the Dock icon and the app menu. Because this is a
// plain SwiftPM executable, Accessibility permission is granted to the terminal (or the built
// binary) that runs it, not to an app bundle.

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
