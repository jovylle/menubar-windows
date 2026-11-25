// WindowProvider.swift
// Lists the windows that can be shown as tabs.
//
// Gotchas:
// - CGWindowList gives IDs, bounds, layer and alpha. Titles from CGWindowList need Screen Recording
//   permission, so titles and focus come from AX instead. Only Accessibility is required.
// - A CG window is kept only if AX also reports it (matched by CGWindowID, then by bounds). That
//   drops tooltips, helper panels and other layer-0 windows that AX does not list.
// - Helper windows: some apps (Edge's Find bar, popovers) expose real AX windows. With "Ignore small
//   helper windows" on, a window is dropped when the app reports an AX subrole other than
//   AXStandardWindow or AXDialog, or when either side is smaller than the configured size. With it off,
//   only the original size floor (wider than 80, taller than 40) applies.
// - Minimized windows are not in the on-screen CG list. When "Include minimized windows" is on, they are
//   read from AX per regular app (AXMinimized), which costs one AX round trip per app per refresh.
// - Ordering is NOT done here. TabOrdering (MenubarWindowsCore) orders the result per the user's mode.
//   Never sort by CG z-order: it changes on every click and would reshuffle tabs under the cursor.
// - Screen membership uses the window's CENTER in Cocoa coordinates.

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

    func label(_ mode: TabLabelMode) -> String {
        TabLabel.text(appName: appName, title: title, mode: mode)
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
    /// Windows at or below this size are always ignored (the original rule: keep only size > 80x40).
    static let minimumWidth: CGFloat = 80
    static let minimumHeight: CGFloat = 40
    /// Subroles that count as real windows when the app reports one.
    static let windowSubroles: Set<String> = ["AXStandardWindow", "AXDialog"]

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
        guard size.width > minimumWidth, size.height > minimumHeight else { return false }
        guard filter.ignoreSmallWindows else { return true }
        if let subrole, !subrole.isEmpty, !windowSubroles.contains(subrole) { return false }
        return size.width >= filter.smallWindowSize && size.height >= filter.smallWindowSize
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

        let ownPID = ProcessInfo.processInfo.processIdentifier
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let focusedID = frontmostPID.flatMap { focusedWindowID(pid: $0) }
        var axCache: [pid_t: [AXWindow]] = [:]
        var result: [WindowInfo] = []
        var seen = Set<CGWindowID>()

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
            guard pid != ownPID, cgBounds.width > minimumWidth, cgBounds.height > minimumHeight else {
                continue
            }

            let frame = MenuBarGeometry.cocoaRect(fromTopLeft: cgBounds)
            let windowID = CGWindowID(truncatingIfNeeded: number)
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
            result.append(WindowInfo(
                windowID: windowID,
                pid: pid,
                appKey: appKey(pid: pid, fallbackName: appName),
                appName: appName,
                title: ax.title,
                frame: frame,
                isFocused: windowID == focusedID,
                isMinimized: false
            ))
        }

        if filter.includeMinimized {
            result += minimizedWindows(excluding: seen, ownPID: ownPID, cache: &axCache, filter: filter)
        }
        return result
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

    static func focusedWindowID(pid: pid_t) -> CGWindowID? {
        let app = AXUIElementCreateApplication(pid)
        AX.setTimeout(app)
        guard let window = AX.element(app, "AXFocusedWindow") else { return nil }
        return AX.windowID(window)
    }
}
