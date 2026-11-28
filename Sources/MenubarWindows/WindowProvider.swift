// WindowProvider.swift
// Lists the windows that can be shown as tabs.
//
// Gotchas:
// - CGWindowList gives IDs, bounds, layer and alpha. Titles from CGWindowList need Screen Recording
//   permission, so titles and focus come from AX instead. Only Accessibility is required.
// - A CG window is kept only if AX also reports it (matched by CGWindowID, then by bounds). That
//   drops tooltips, helper panels and other layer-0 windows that AX does not list.
// - Helper windows: some apps (Edge's Find bar, popovers) expose real AX windows. The size and subrole
//   rules live in WindowFilterRule (MenubarWindowsCore), with unit tests.
// - Focus: the active tab is the frontmost app's AXFocusedWindow, or its AXMainWindow when the focused
//   window has no tab (a Find bar or popover has focus), matched by CGWindowID or by AX element. A
//   lookup that times out keeps the previous active tab of that app. See FocusMatch.
// - Minimized windows are not in the on-screen CG list. When "Include minimized windows" is on, they are
//   read from AX per regular app (AXMinimized), which costs one AX round trip per app per refresh.
// - Ordering is NOT done here. TabOrdering (MenubarWindowsCore) orders the result per the user's mode.
//   Never sort by CG z-order: it changes on every click and would reshuffle tabs under the cursor.
// - Screen membership uses the window's CENTER in Cocoa coordinates.
// - Own windows: this process is excluded from the AX path (its AX calls stall on the main thread). The one
//   exception is the Settings window (OwnWindowRule), read in-process from NSApp.windows, with its title
//   and frame from NSWindow and CG. Its focus and minimized state also come from NSWindow.

import AppKit
import ApplicationServices
import MenubarWindowsCore

struct WindowInfo {
    let windowID: CGWindowID
    let pid: pid_t
    /// Bundle identifier, or the app name when the app has none. Used for pinning.
    let appKey: String
    let appName: String
    let title: String
    /// Cocoa coordinates.
    let frame: CGRect
    let isFocused: Bool
    let isMinimized: Bool

    var snapshot: WindowSnapshot {
        WindowSnapshot(
            windowID: windowID, pid: pid, appKey: appKey, appName: appName, title: title, frame: frame
        )
    }

    /// A copy marked as the focused window.
    func focused() -> WindowInfo {
        WindowInfo(
            windowID: windowID, pid: pid, appKey: appKey, appName: appName, title: title,
            frame: frame, isFocused: true, isMinimized: isMinimized
        )
    }

    /// The tab label. `customName` comes from the user's rename (TabNameOverrides), not from the window.
    func label(_ mode: TabLabelMode, customName: String? = nil) -> String {
        TabLabel.text(appName: appName, title: title, mode: mode, customName: customName)
    }
}

struct WindowFilter {
    var includeMinimized = false
    var ignoreSmallWindows = true
    var smallWindowSize: CGFloat = 100

    static var current: WindowFilter {
        let settings = Settings.shared
        return WindowFilter(
            includeMinimized: settings.includeMinimized,
            ignoreSmallWindows: settings.ignoreSmallWindows,
            smallWindowSize: CGFloat(settings.smallWindowSize)
        )
    }
}

enum WindowProvider {
    static let minimumWidth = WindowFilterRule.minimumWidth
    static let minimumHeight = WindowFilterRule.minimumHeight
    /// The tab that was active on the last refresh, with its app, for FocusMatch's timeout rule.
    nonisolated(unsafe) private static var lastActive: (pid: pid_t, windowID: CGWindowID)?

    struct AXWindow {
        let element: AXUIElement
        let windowID: CGWindowID?
        let title: String
        let subrole: String?
        let isMinimized: Bool
        /// Top-left global coordinates, as AX reports them.
        let frame: CGRect
    }

    static func axWindows(pid: pid_t) -> [AXWindow] {
        let app = AXUIElementCreateApplication(pid)
        AX.setTimeout(app)
        return AX.elements(app, "AXWindows").map { element in
            AXWindow(
                element: element,
                windowID: AX.windowID(element),
                title: AX.string(element, "AXTitle") ?? "",
                subrole: AX.string(element, "AXSubrole"),
                isMinimized: (AX.copy(element, "AXMinimized") as? Bool) ?? false,
                frame: CGRect(
                    origin: AX.point(element, "AXPosition") ?? .zero,
                    size: AX.size(element, "AXSize") ?? .zero
                )
            )
        }
    }

    static func passesFilter(size: CGSize, subrole: String?, filter: WindowFilter) -> Bool {
        WindowFilterRule.passes(
            size: size,
            subrole: subrole,
            ignoreSmallWindows: filter.ignoreSmallWindows,
            smallWindowSize: filter.smallWindowSize
        )
    }

    static func appKey(pid: pid_t, fallbackName: String) -> String {
        NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? fallbackName
    }

    /// Every window that AX can see, across all screens, unordered.
    static func allWindows(filter: WindowFilter = .current) -> [WindowInfo] {
        guard AXIsProcessTrusted(),
              let raw = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else {
            return []
        }

        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        var axCache: [pid_t: [AXWindow]] = [:]
        var result: [WindowInfo] = []
        var seen = Set<CGWindowID>()
        /// The frontmost app's tabs and their AX elements, for focus matching.
        var frontmostTabs: [(windowID: CGWindowID, element: AXUIElement)] = []

        for entry in raw {
            guard (entry[kCGWindowLayer as String] as? Int) == 0,
                  ((entry[kCGWindowAlpha as String] as? Double) ?? 0) > 0,
                  let pidNumber = entry[kCGWindowOwnerPID as String] as? Int,
                  let number = entry[kCGWindowNumber as String] as? Int,
                  let boundsDict = entry[kCGWindowBounds as String] as? [String: Any],
                  let cgBounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else {
                continue
            }
            let pid = pid_t(pidNumber)
            guard cgBounds.width > minimumWidth, cgBounds.height > minimumHeight else {
                continue
            }

            let frame = MenuBarGeometry.cocoaRect(fromTopLeft: cgBounds)
            let windowID = CGWindowID(truncatingIfNeeded: number)
            if pid == ownPID {
                // Only the Settings window; every other own window is skipped. No AX for our own process.
                guard let own = ownTabWindow(windowID: windowID) else { continue }
                seen.insert(windowID)
                result.append(ownWindowInfo(own, windowID: windowID, frame: frame, isMinimized: false))
                continue
            }
            if axCache[pid] == nil {
                axCache[pid] = axWindows(pid: pid)
            }
            guard let ax = findAXWindow(windowID: windowID, frame: frame, in: axCache[pid] ?? []),
                  passesFilter(size: cgBounds.size, subrole: ax.subrole, filter: filter) else {
                continue
            }

            let appName = NSRunningApplication(processIdentifier: pid)?.localizedName
                ?? (entry[kCGWindowOwnerName as String] as? String)
                ?? "App"
            seen.insert(windowID)
            if pid == frontmostPID { frontmostTabs.append((windowID, ax.element)) }
            result.append(WindowInfo(
                windowID: windowID,
                pid: pid,
                appKey: appKey(pid: pid, fallbackName: appName),
                appName: appName,
                title: ax.title,
                frame: frame,
                isFocused: false,
                isMinimized: false
            ))
        }

        if let frontmostPID {
            let activeID = frontmostPID == ownPID
                ? ownActiveWindowID()
                : activeWindowID(pid: frontmostPID, tabs: frontmostTabs)
            if let activeID, let index = result.firstIndex(where: { $0.windowID == activeID }) {
                result[index] = result[index].focused()
            }
        }

        if filter.includeMinimized {
            result += ownMinimizedWindows(excluding: seen)
            result += minimizedWindows(excluding: seen, ownPID: ownPID, cache: &axCache, filter: filter)
        }
        return result
    }

    static var ownPID: pid_t { ProcessInfo.processInfo.processIdentifier }

    /// The Settings window with this CG window number, read in-process. Nil for every other own window.
    static func ownTabWindow(windowID: CGWindowID) -> NSWindow? {
        NSApp.windows.first { window in
            OwnWindowRule.isTabWindow(identifier: window.identifier?.rawValue)
                && CGWindowID(truncatingIfNeeded: window.windowNumber) == windowID
        }
    }

    /// The key window's tab ID when this app is frontmost and the key window is a tab (Settings).
    private static func ownActiveWindowID() -> CGWindowID? {
        guard let key = NSApp.keyWindow,
              OwnWindowRule.isTabWindow(identifier: key.identifier?.rawValue) else {
            return nil
        }
        return CGWindowID(truncatingIfNeeded: key.windowNumber)
    }

    /// Minimized own tab windows (the Settings window when it is miniaturized).
    private static func ownMinimizedWindows(excluding seen: Set<CGWindowID>) -> [WindowInfo] {
        NSApp.windows.compactMap { window in
            let windowID = CGWindowID(truncatingIfNeeded: window.windowNumber)
            guard OwnWindowRule.isTabWindow(identifier: window.identifier?.rawValue),
                  window.isMiniaturized, !seen.contains(windowID) else {
                return nil
            }
            return ownWindowInfo(window, windowID: windowID, frame: window.frame, isMinimized: true)
        }
    }

    private static func ownWindowInfo(_ window: NSWindow, windowID: CGWindowID, frame: CGRect, isMinimized: Bool) -> WindowInfo {
        let appName = NSRunningApplication.current.localizedName ?? AppInfo.displayName
        return WindowInfo(
            windowID: windowID,
            pid: ownPID,
            appKey: appKey(pid: ownPID, fallbackName: appName),
            appName: appName,
            title: window.title,
            frame: frame,
            isFocused: false,
            isMinimized: isMinimized
        )
    }

    /// Minimized windows of regular apps, read from AX. Their frame is the last on-screen frame.
    private static func minimizedWindows(
        excluding seen: Set<CGWindowID>,
        ownPID: pid_t,
        cache: inout [pid_t: [AXWindow]],
        filter: WindowFilter
    ) -> [WindowInfo] {
        var result: [WindowInfo] = []
        for app in NSWorkspace.shared.runningApplications
        where app.activationPolicy == .regular && app.processIdentifier != ownPID {
            let pid = app.processIdentifier
            if cache[pid] == nil {
                cache[pid] = axWindows(pid: pid)
            }
            for ax in cache[pid] ?? [] where ax.isMinimized {
                guard let windowID = ax.windowID, !seen.contains(windowID),
                      passesFilter(size: ax.frame.size, subrole: ax.subrole, filter: filter) else {
                    continue
                }
                let appName = app.localizedName ?? "App"
                result.append(WindowInfo(
                    windowID: windowID,
                    pid: pid,
                    appKey: app.bundleIdentifier ?? appName,
                    appName: appName,
                    title: ax.title,
                    frame: MenuBarGeometry.cocoaRect(fromTopLeft: ax.frame),
                    isFocused: false,
                    isMinimized: true
                ))
            }
        }
        return result
    }

    /// IDs of every layer-0 window that still exists, on screen or not. Used to forget closed windows
    /// in the order tracker without forgetting windows that are merely on another Space.
    static func aliveWindowIDs() -> Set<UInt32> {
        let raw = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        var ids = Set<UInt32>()
        for entry in raw where (entry[kCGWindowLayer as String] as? Int) == 0 {
            if let number = entry[kCGWindowNumber as String] as? Int {
                ids.insert(UInt32(truncatingIfNeeded: number))
            }
        }
        return ids
    }

    /// Windows whose center lies on the given screen.
    static func windows(on screen: NSScreen, in all: [WindowInfo]) -> [WindowInfo] {
        all.filter { screen.frame.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY)) }
    }

    /// The AX window for a CG window: exact CGWindowID match first, then bounds within 2pt.
    static func findAXWindow(windowID: CGWindowID, frame: CGRect, in list: [AXWindow]) -> AXWindow? {
        if let exact = list.first(where: { $0.windowID == windowID }) {
            return exact
        }
        return list.first(where: { candidate in
            let axFrame = MenuBarGeometry.cocoaRect(fromTopLeft: candidate.frame)
            return abs(axFrame.minX - frame.minX) <= 2
                && abs(axFrame.minY - frame.minY) <= 2
                && abs(axFrame.width - frame.width) <= 2
                && abs(axFrame.height - frame.height) <= 2
        })
    }

    /// The frontmost app's tab to mark active: its focused window, else its main window. See FocusMatch.
    private static func activeWindowID(
        pid: pid_t,
        tabs: [(windowID: CGWindowID, element: AXUIElement)]
    ) -> CGWindowID? {
        let app = AXUIElementCreateApplication(pid)
        AX.setTimeout(app)
        var timedOut = false
        func tabID(_ attribute: String) -> CGWindowID? {
            let (value, error) = AX.copyResult(app, attribute)
            if error == .cannotComplete { timedOut = true }
            guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
            let element = value as! AXUIElement
            let id = AX.windowID(element)
            return tabs.first(where: { $0.windowID == id || CFEqual($0.element, element) })?.windowID
        }
        let focused = tabID("AXFocusedWindow")
        let main = focused == nil ? tabID("AXMainWindow") : nil
        let previous = lastActive.flatMap { $0.pid == pid ? $0.windowID : nil }
        let active = FocusMatch.activeWindow(
            focused: focused, main: main, lookupTimedOut: timedOut,
            previous: previous, candidates: tabs.map(\.windowID)
        )
        lastActive = active.map { (pid, $0) }
        return active
    }

    static func focusedWindowID(pid: pid_t) -> CGWindowID? {
        let app = AXUIElementCreateApplication(pid)
        AX.setTimeout(app)
        guard let window = AX.element(app, "AXFocusedWindow") else { return nil }
        return AX.windowID(window)
    }
}
