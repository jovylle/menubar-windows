// WindowRaiser.swift
// Brings a window forward: AXRaise on the exact AX window, then activates the owning app.
//
// Gotchas:
// - AXFrontmost on the app element is what makes the switch reliable from a background app.
// - AXRaise alone does not always move focus to the owning app, so the app is activated too.
// - activate(options: [.activateIgnoringOtherApps]) is deprecated on macOS 14+, so the newer
//   activate() is used there.
// - The AX window is re-matched at click time rather than cached, because windows can move
//   or close between refreshes.

import AppKit
import ApplicationServices

enum WindowRaiser {
    static func raise(_ window: WindowInfo) {
        // Setting AXFrontmost on the app element works even when this accessory app is not active.
        // On macOS 14+ a plain activate() from a background app can be ignored.
        let appElement = AXUIElementCreateApplication(window.pid)
        _ = AXUIElementSetAttributeValue(appElement, "AXFrontmost" as CFString, kCFBooleanTrue)

        let candidates = WindowProvider.axWindows(pid: window.pid)
        if let target = WindowProvider.findAXWindow(windowID: window.windowID, frame: window.frame, in: candidates) {
            _ = AXUIElementSetAttributeValue(target.element, "AXMain" as CFString, kCFBooleanTrue)
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
