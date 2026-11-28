// TabNameOverrides.swift
// The custom tab names from "Rename Tab…", keyed by window ID. Pure, so the rules (one line, trimmed,
// blank means reset, closed windows dropped) are unit tested. The strip only reads the result.
//
// Gotchas:
// - Memory only. A CGWindowID does not survive a restart, and no other identity is stable: titles change
//   and many windows share a bundle ID. A name saved across a restart could land on the wrong window, so
//   names are not persisted. Same rule as the manual tab order (WindowOrderTracker).
// - A name replaces the tab's label only. The real window title stays in the tooltip and VoiceOver text.
// - Blank input is not a name. It removes the override, so the tab shows its own label again.
// - Pruning runs with the order tracker's prune (about every 10 seconds), so a name can outlive its window
//   for that long. The window ID is the only key: a new window that reuses a closed ID would inherit the name.

import Foundation

public struct TabNameOverrides: Equatable, Sendable {
    private var names: [UInt32: String] = [:]

    public init() {}

    /// The custom name for a window, or nil when its tab shows its own label.
    public func name(for windowID: UInt32) -> String? {
        names[windowID]
    }

    /// The typed text as one trimmed line. Nil when nothing is left, which means "reset".
    public static func clean(_ input: String) -> String? {
        let oneLine = input
            .components(separatedBy: .newlines)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return oneLine.isEmpty ? nil : oneLine
    }

    /// Sets the name for a window. Blank input removes it. Returns true when the stored name changed.
    @discardableResult
    public mutating func rename(_ windowID: UInt32, to input: String) -> Bool {
        let cleaned = Self.clean(input)
        guard names[windowID] != cleaned else { return false }
        names[windowID] = cleaned
        return true
    }

    /// Removes a window's custom name, so its tab shows its own label again.
    public mutating func reset(_ windowID: UInt32) {
        names[windowID] = nil
    }

    /// Keeps only the names of windows that still exist.
    public mutating func prune(keeping alive: Set<UInt32>) {
        names = names.filter { alive.contains($0.key) }
    }
}
