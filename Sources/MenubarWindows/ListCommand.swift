// ListCommand.swift
// `--list`: prints the detected free strip and the window list for each screen, then exits.
// Use it to check geometry and Accessibility without starting the UI.

import AppKit
import ApplicationServices

enum ListCommand {
    static func run() {
        let trusted = AXIsProcessTrusted()
        print("Accessibility trusted: \(trusted)")
        print("Frontmost app: \(NSWorkspace.shared.frontmostApplication?.localizedName ?? "none")")
        print("Frontmost window full screen: \(MenuBarGeometry.frontmostIsFullScreen())")

        let windows = trusted ? WindowProvider.allWindows() : []
        if !trusted {
            print("(Accessibility not granted: window list is empty and strip titles use the fallback offset)")
        }

        for (index, screen) in NSScreen.screens.enumerated() {
            print("")
            print("Screen \(index): frame \(describe(screen.frame)), "
                + "reserved menu bar \(String(format: "%.0f", MenuBarGeometry.reservedMenuBarHeight(screen)))pt")
            if let strip = MenuBarGeometry.freeStrip(on: screen) {
                print("  free strip: \(describe(strip.frame)), left edge from \(strip.leftSource)")
            } else {
                print("  free strip: hidden (menu bar not reserved, full screen, or no room)")
            }

            let onScreen = WindowProvider.windows(on: screen, in: windows)
            print("  windows (\(onScreen.count)):")
            for window in onScreen {
                print("    app=\"\(window.appName)\" title=\"\(window.title)\" "
                    + "focused=\(window.isFocused) id=\(window.windowID) pid=\(window.pid)")
            }
        }
    }

    private static func describe(_ rect: NSRect) -> String {
        String(format: "x=%.0f y=%.0f w=%.0f h=%.0f", rect.minX, rect.minY, rect.width, rect.height)
    }
}
