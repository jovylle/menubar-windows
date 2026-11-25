// WindowRaiser.swift
// Window actions: raise (bring forward and activate its app), close and minimize.
//
// Gotchas:
// - AXFrontmost on the app element is what makes the switch reliable from a background app.
// - AXRaise alone does not always move focus to the owning app, so the app is activated too.
// - activate(options: [.activateIgnoringOtherApps]) is deprecated on macOS 14+, so the newer
//   activate() is used there.
// - The AX window is re-matched at action time rather than cached, because windows can move
//   or close between refreshes.
// - A minimized window must be un-minimized (AXMinimized = false) before AXRaise has any effect.
// - Close presses the window's own AXCloseButton, so the app runs its normal close path (it may ask to
//   save). Nothing is force-closed.

import AppKit
import ApplicationServices

enum WindowRaiser {
    static func raise(_ window: WindowInfo) {
        // Setting AXFrontmost on the app element works even when this accessory app is not active.
        // On macOS 14+ a plain activate() from a background app can be ignored.
        let appElement = AXUIElementCreateApplication(window.pid)
        _ = AXUIElementSetAttributeValue(appElement, "AXFrontmost" as CFString, kCFBooleanTrue)

        if let target = axWindow(for: window) {
            if target.isMinimized {
                _ = AXUIElementSetAttributeValue(target.element, "AXMinimized" as CFString, kCFBooleanFalse)
            }
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

    static func close(_ window: WindowInfo) {
        guard let target = axWindow(for: window),
              let button = AX.element(target.element, "AXCloseButton") else {
            NSSound.beep()
            return
        }
        _ = AXUIElementPerformAction(button, "AXPress" as CFString)
    }

    static func minimize(_ window: WindowInfo) {
        guard let target = axWindow(for: window) else {
            NSSound.beep()
            return
        }
        let result = AXUIElementSetAttributeValue(target.element, "AXMinimized" as CFString, kCFBooleanTrue)
        if result != .success, let button = AX.element(target.element, "AXMinimizeButton") {
            _ = AXUIElementPerformAction(button, "AXPress" as CFString)
        }
    }

    private static func axWindow(for window: WindowInfo) -> WindowProvider.AXWindow? {
        let candidates = WindowProvider.axWindows(pid: window.pid)
        // Minimized windows have no on-screen CG frame to match, so they rely on the CGWindowID.
        return WindowProvider.findAXWindow(windowID: window.windowID, frame: window.frame, in: candidates)
    }
}
