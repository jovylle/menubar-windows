// WindowRaiser.swift
// Brings a window forward: AXRaise on the exact AX window, then activates the owning app.
//
// Gotchas:
// - AXRaise alone does not always move focus to the owning app, so the app is activated too.
// - activate(options: [.activateIgnoringOtherApps]) is deprecated on macOS 14+, so the newer
//   activate() is used there.
// - The AX window is re-matched at click time rather than cached, because windows can move
//   or close between refreshes.

import AppKit
import ApplicationServices

enum WindowRaiser {
    static func raise(_ window: WindowInfo) {
        let candidates = WindowProvider.axWindows(pid: window.pid)
        if let target = WindowProvider.findAXWindow(windowID: window.windowID, frame: window.frame, in: candidates) {
            _ = AXUIElementPerformAction(target.element, "AXRaise" as CFString)
        }

        guard let app = NSRunningApplication(processIdentifier: window.pid) else { return }
        if #available(macOS 14.0, *) {
            app.activate()
        } else {
            app.activate(options: [.activateIgnoringOtherApps])
        }
    }
}
