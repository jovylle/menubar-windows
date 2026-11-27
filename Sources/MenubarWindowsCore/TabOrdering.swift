// TabOrdering.swift
// Pure tab ordering: given a snapshot of windows and the user's order mode, returns the tab order.
// No AppKit, no Accessibility, so it is unit tested in Tests/MenubarWindowsCoreTests.
//
// Gotchas:
// - "Automatic" uses first-seen order kept by WindowOrderTracker, NOT the CG z-order. Z-order changes
//   on every click, which would reshuffle tabs under the cursor. A window keeps its slot for as long as
//   it lives; new windows go last.
// - Windows that appear in the same refresh (for example at launch) get first-seen numbers in app name,
//   then window ID order, so the initial order is deterministic.
// - Every mode breaks ties with first-seen order, then window ID, so the result is always total and
//   stable across refreshes.
// - Frames are in Cocoa coordinates (bottom-left origin): a larger maxY means higher on screen.
// - `manual` is the only mode that uses a stored list (the order the user dragged tabs into). That list
//   lives in WindowOrderTracker, in memory only: window IDs do not survive a restart. Windows not in the
//   list (new ones) go last, in automatic order. Closed windows drop out when the tracker prunes.

import CoreGraphics
import Foundation

public enum TabOrderMode: String, CaseIterable, Identifiable, Sendable {
    case automatic
    case recentFirst
    case appName
    case leftToRight
    case pinnedFirst
    case manual

    public var id: String { rawValue }

    /// Name shown in Settings, the preview and `--list`.
    public var title: String {
        switch self {
        case .automatic: return "Automatic"
        case .recentFirst: return "Most recently used first"
        case .appName: return "App name A to Z"
        case .leftToRight: return "Left to right on screen"
        case .pinnedFirst: return "Pinned apps first, then automatic"
        case .manual: return "Custom (drag tabs to arrange)"
        }
    }

    /// One-line help text shown under the picker.
    public var help: String {
        switch self {
        case .automatic:
            return "Keeps a stable order. A new window gets the last tab; clicking never reshuffles."
        case .recentFirst:
            return "The window you used last comes first. Tabs move as you switch."
        case .appName:
            return "Sorted by app name; windows of one app keep their automatic order."
        case .leftToRight:
            return "Follows where windows sit on screen, by their left edge."
        case .pinnedFirst:
            return "Apps you pin (right-click a tab) come first in pin order, then the rest automatically."
        case .manual:
            return "Drag a tab in the strip to move it. Until then, the order is automatic. Lasts until you quit."
        }
    }
}

/// The ordering input for one window.
public struct WindowSnapshot: Equatable, Sendable {
    public let windowID: UInt32
    public let pid: Int32
    /// Stable app identity used for pinning: the bundle identifier, or the app name as a fallback.
    public let appKey: String
    public let appName: String
    public let title: String
    /// Cocoa coordinates (bottom-left origin).
    public let frame: CGRect
    public let lastFocusedAt: Date?

    public init(
        windowID: UInt32,
        pid: Int32,
        appKey: String,
        appName: String,
        title: String,
        frame: CGRect,
        lastFocusedAt: Date? = nil
    ) {
        self.windowID = windowID
        self.pid = pid
        self.appKey = appKey
        self.appName = appName
        self.title = title
        self.frame = frame
        self.lastFocusedAt = lastFocusedAt
    }
}

public enum TabOrdering {
    /// Orders windows for display.
    /// - Parameters:
    ///   - firstSeen: first-seen sequence numbers from WindowOrderTracker. Windows without one sort
    ///     after those with one, by window ID.
    ///   - pinnedApps: app keys in pin order. Only used by `.pinnedFirst`.
    ///   - manualOrder: window IDs in the order the user dragged them into. Only used by `.manual`.
    ///     IDs missing from it go last, in automatic order.
    public static func order(
        _ windows: [WindowSnapshot],
        mode: TabOrderMode,
        firstSeen: [UInt32: Int],
        pinnedApps: [String] = [],
        manualOrder: [UInt32] = []
    ) -> [WindowSnapshot] {
        func automaticLess(_ a: WindowSnapshot, _ b: WindowSnapshot) -> Bool {
            let sa = firstSeen[a.windowID] ?? Int.max
            let sb = firstSeen[b.windowID] ?? Int.max
            return sa != sb ? sa < sb : a.windowID < b.windowID
        }

        switch mode {
        case .automatic:
            return windows.sorted(by: automaticLess)

        case .recentFirst:
            return windows.sorted { a, b in
                switch (a.lastFocusedAt, b.lastFocusedAt) {
                case let (x?, y?) where x != y: return x > y
                case (_?, nil): return true
                case (nil, _?): return false
                default: return automaticLess(a, b)
                }
            }

        case .appName:
            return windows.sorted { a, b in
                let result = a.appName.localizedStandardCompare(b.appName)
                return result == .orderedSame ? automaticLess(a, b) : result == .orderedAscending
            }

        case .leftToRight:
            return windows.sorted { a, b in
                if a.frame.minX != b.frame.minX { return a.frame.minX < b.frame.minX }
                if a.frame.maxY != b.frame.maxY { return a.frame.maxY > b.frame.maxY }
                return automaticLess(a, b)
            }

        case .pinnedFirst:
            var rank: [String: Int] = [:]
            for (index, key) in pinnedApps.enumerated() where rank[key] == nil {
                rank[key] = index
            }
            return windows.sorted { a, b in
                let ra = rank[a.appKey] ?? Int.max
                let rb = rank[b.appKey] ?? Int.max
                return ra != rb ? ra < rb : automaticLess(a, b)
            }

        case .manual:
            var rank: [UInt32: Int] = [:]
            for (index, id) in manualOrder.enumerated() where rank[id] == nil {
                rank[id] = index
            }
            return windows.sorted { a, b in
                let ra = rank[a.windowID] ?? Int.max
                let rb = rank[b.windowID] ?? Int.max
                return ra != rb ? ra < rb : automaticLess(a, b)
            }
        }
    }

    /// Moves the item at `from` to `to` (its index in the resulting list). Indices are clamped to the
    /// list, so an out-of-range target lands at the nearest end. Returns the list unchanged when `from`
    /// is out of range.
    public static func move(_ ids: [UInt32], from: Int, to: Int) -> [UInt32] {
        guard ids.indices.contains(from) else { return ids }
        var result = ids
        let id = result.remove(at: from)
        result.insert(id, at: min(max(0, to), result.count))
        return result
    }
}

/// Remembers when each window was first seen and last focused. Fed by the app's refresh loop and by
/// NSWorkspace activation. Entries are dropped only when a window no longer exists, so a window that is
/// briefly off screen (another Space, minimized) keeps its slot.
public final class WindowOrderTracker {
    public private(set) var firstSeen: [UInt32: Int] = [:]
    public private(set) var lastFocused: [UInt32: Date] = [:]
    /// The order the user built by dragging tabs (`.manual`). Memory only.
    public private(set) var manualOrder: [UInt32] = []
    private var nextSequence = 0

    public init() {}

    /// Assigns first-seen numbers to windows not seen before. New windows that arrive together are
    /// numbered by app name, then window ID.
    public func observe(_ windows: [WindowSnapshot]) {
        let fresh = windows
            .filter { firstSeen[$0.windowID] == nil }
            .sorted { a, b in
                let result = a.appName.localizedStandardCompare(b.appName)
                return result == .orderedSame ? a.windowID < b.windowID : result == .orderedAscending
            }
        for window in fresh where firstSeen[window.windowID] == nil {
            firstSeen[window.windowID] = nextSequence
            nextSequence += 1
        }
    }

    public func noteFocused(_ windowID: UInt32, at date: Date = Date()) {
        lastFocused[windowID] = date
    }

    /// Forgets windows that are gone for good.
    public func prune(keeping alive: Set<UInt32>) {
        firstSeen = firstSeen.filter { alive.contains($0.key) }
        lastFocused = lastFocused.filter { alive.contains($0.key) }
        manualOrder = manualOrder.filter { alive.contains($0) }
    }

    /// Drops the manual order, so the next drag starts again from the order on screen.
    public func resetManualOrder() {
        manualOrder = []
    }

    /// Applies a drag. `visible` is the order on screen for one strip, in the order the user sees it.
    /// The window moves from `from` to `to` within it. Windows outside `visible` (other screens, or
    /// overflow) keep their relative order after it.
    public func moveManual(from: Int, to: Int, visible: [UInt32]) {
        let rest = manualOrder.filter { !visible.contains($0) }
        manualOrder = TabOrdering.move(visible, from: from, to: to) + rest
    }

    /// Returns the snapshots with `lastFocusedAt` filled from this tracker.
    public func withFocusTimes(_ windows: [WindowSnapshot]) -> [WindowSnapshot] {
        windows.map { window in
            WindowSnapshot(
                windowID: window.windowID,
                pid: window.pid,
                appKey: window.appKey,
                appName: window.appName,
                title: window.title,
                frame: window.frame,
                lastFocusedAt: lastFocused[window.windowID] ?? window.lastFocusedAt
            )
        }
    }

    /// Convenience: observe, then order.
    public func ordered(
        _ windows: [WindowSnapshot],
        mode: TabOrderMode,
        pinnedApps: [String] = []
    ) -> [WindowSnapshot] {
        observe(windows)
        return TabOrdering.order(
            withFocusTimes(windows),
            mode: mode,
            firstSeen: firstSeen,
            pinnedApps: pinnedApps,
            manualOrder: manualOrder
        )
    }
}
