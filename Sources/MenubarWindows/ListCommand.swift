// ListCommand.swift
// `--list`: prints the active settings that shape the strip, the detected strip region and the window
// list (in the active tab order) for each screen, then exits. Use it to check geometry and
// Accessibility without starting the UI. It is also the headless check for the built app bundle.

import AppKit
import ApplicationServices
import MenubarWindowsCore

enum ListCommand {
    static func run() {
        let settings = Settings.shared
        let trusted = AXIsProcessTrusted()
        print("\(AppInfo.displayName) \(AppInfo.version) (\(Bundle.main.bundleIdentifier ?? "no bundle"))")
        print("Accessibility trusted: \(trusted)")
        print("Tab order: \(settings.order.title)")
        print("Labels: \(settings.label.title), max tabs \(settings.maxTabs), "
            + "width \(settings.widthMode.rawValue) \(Int(settings.stripWidth))pt, align \(settings.alignment.rawValue)")
        print("Filters: minimized \(settings.includeMinimized ? "included" : "excluded"), "
            + "small helper windows \(settings.ignoreSmallWindows ? "ignored below \(Int(settings.smallWindowSize))pt" : "kept")")
        print("Frontmost app: \(NSWorkspace.shared.frontmostApplication?.localizedName ?? "none")")
        print("Frontmost window full screen: \(MenuBarGeometry.frontmostIsFullScreen())")

        let windows = trusted ? WindowProvider.allWindows() : []
        if !trusted {
            print("(Accessibility not granted: window list is empty and strip titles use the fallback offset)")
        }
        let tracker = WindowOrderTracker()

        for (index, screen) in NSScreen.screens.enumerated() {
            let uuid = Displays.uuid(of: screen)
            print("")
            print("Screen \(index): \"\(Displays.name(of: screen))\" frame \(describe(screen.frame)), "
                + "reserved menu bar \(String(format: "%.0f", MenuBarGeometry.reservedMenuBarHeight(screen)))pt, "
                + "enabled \(settings.isDisplayEnabled(uuid))")
            if let strip = MenuBarGeometry.freeStrip(
                on: screen,
                width: CGFloat(settings.stripWidth),
                alignment: settings.alignment,
                hideInFullScreen: settings.hideInFullScreen
            ) {
                print("  strip region: \(describe(strip.frame)), \(strip.leftSource)")
            } else {
                print("  strip region: hidden (menu bar not reserved, full screen, or no room)")
            }

            let onScreen = WindowProvider.windows(on: screen, in: windows)
            let byID = Dictionary(onScreen.map { ($0.windowID, $0) }, uniquingKeysWith: { first, _ in first })
            let ordered = tracker
                .ordered(onScreen.map(\.snapshot), mode: settings.order, pinnedApps: settings.pinnedApps)
                .compactMap { byID[$0.windowID] }
            print("  windows (\(ordered.count)), in tab order:")
            for window in ordered {
                print("    app=\"\(window.appName)\" title=\"\(window.title)\" label=\"\(window.label(settings.label))\" "
                    + "focused=\(window.isFocused) minimized=\(window.isMinimized) id=\(window.windowID) pid=\(window.pid)")
            }
        }
    }

    private static func describe(_ rect: NSRect) -> String {
        String(format: "x=%.0f y=%.0f w=%.0f h=%.0f", rect.minX, rect.minY, rect.width, rect.height)
    }
}
