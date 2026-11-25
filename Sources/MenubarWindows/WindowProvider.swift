// WindowProvider.swift
// Lists the windows that can be shown as pills.
//
// Gotchas:
// - CGWindowList gives IDs, bounds, layer and alpha. Titles from CGWindowList need Screen Recording
//   permission, so titles and focus come from AX instead. Only Accessibility is required.
// - A CG window is kept only if AX also reports it (matched by CGWindowID, then by bounds). That
//   drops tooltips, helper panels and other layer-0 windows that AX does not list.
// - Ordering: by app name, then window ID. CG z-order changes on every click, which would reshuffle
//   the pills under the user's cursor.
// - Screen membership uses the window's CENTER in Cocoa coordinates.

import AppKit
import ApplicationServices

struct WindowInfo {
    let windowID: CGWindowID
    let pid: pid_t
    let appName: String
    let title: String
    /// Cocoa coordinates.
    let frame: CGRect
    let isFocused: Bool

    /// "App: title", on one line and truncated to 22 characters. Titles can contain newlines.
    var displayText: String {
        let oneLine = title
            .components(separatedBy: .newlines)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        let full = (oneLine.isEmpty || oneLine == appName) ? appName : "\(appName): \(oneLine)"
        return full.truncated(to: 22)
    }
}

extension String {
    func truncated(to limit: Int) -> String {
        count > limit ? String(prefix(limit - 1)) + "…" : self
    }
}

enum WindowProvider {
    /// Windows at or below this size are ignored (spec: keep only size > 80x40).
    static let minimumWidth: CGFloat = 80
    static let minimumHeight: CGFloat = 40

    struct AXWindow {
        let element: AXUIElement
        let windowID: CGWindowID?
        let title: String
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
                frame: CGRect(
                    origin: AX.point(element, "AXPosition") ?? .zero,
                    size: AX.size(element, "AXSize") ?? .zero
                )
            )
        }
    }

    /// Every on-screen window that AX can see, across all screens.
    static func allWindows() -> [WindowInfo] {
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
            guard let ax = findAXWindow(windowID: windowID, frame: frame, in: axCache[pid] ?? []) else {
                continue
            }

            let appName = NSRunningApplication(processIdentifier: pid)?.localizedName
                ?? (entry[kCGWindowOwnerName as String] as? String)
                ?? "App"
            result.append(WindowInfo(
                windowID: windowID,
                pid: pid,
                appName: appName,
                title: ax.title,
                frame: frame,
                isFocused: windowID == focusedID
            ))
        }

        return result.sorted { a, b in
            a.appName == b.appName ? a.windowID < b.windowID : a.appName < b.appName
        }
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
