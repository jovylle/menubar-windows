// DemoData.swift
// Invented windows, apps and displays for demo mode (`-mw.demo YES`), used for screenshots and videos.
// Pure and UI-free so the generation, clamping and ordering are unit tested. The app target turns these
// into WindowInfo values and draws the icons (DemoMode.swift).
//
// Gotchas:
// - Every name here is made up. Demo mode must never show a real app, window title or display name, so
//   anything new shown in demo mode has to come from this file.
// - Window IDs start at 1, frames run left to right on a 1512pt-wide screen, and each window has a
//   different focus time, so every tab order mode gives a defined, different order.
// - Counts and the active index are clamped, so a bad launch argument still gives a valid strip.

import CoreGraphics
import Foundation

public struct DemoApp: Equatable, Sendable {
    public let name: String
    public let title: String
    /// Letter drawn on the generated icon.
    public let letter: String
    /// Icon color, sRGB 0...1.
    public let red: Double
    public let green: Double
    public let blue: Double

    public var appKey: String { "demo.\(name.lowercased())" }
}

public enum DemoData {
    public static let countRange: ClosedRange<Int> = 1...8
    public static let defaultCount = 6
    public static let defaultActiveIndex = 1

    /// The invented apps, in tab order. The first six are the default set.
    public static let apps: [DemoApp] = [
        DemoApp(name: "Draftpad", title: "Launch notes", letter: "D", red: 0.96, green: 0.62, blue: 0.12),
        DemoApp(name: "Shellbox", title: "build", letter: "S", red: 0.20, green: 0.22, blue: 0.26),
        DemoApp(name: "Mockups", title: "v3", letter: "M", red: 0.55, green: 0.36, blue: 0.95),
        DemoApp(name: "Planner", title: "Week", letter: "P", red: 0.17, green: 0.62, blue: 0.95),
        DemoApp(name: "Pagefold", title: "Q3", letter: "F", red: 0.92, green: 0.30, blue: 0.36),
        DemoApp(name: "Statline", title: "Oct", letter: "L", red: 0.16, green: 0.72, blue: 0.45),
        DemoApp(name: "Tunebox", title: "Focus mix", letter: "T", red: 0.95, green: 0.38, blue: 0.68),
        DemoApp(name: "Inkwell", title: "Sketches", letter: "I", red: 0.10, green: 0.60, blue: 0.62)
    ]

    /// Invented display names for Settings, Displays.
    public static let displayNames = ["Built-in Display", "External Display"]

    public static func clampedCount(_ value: Int?) -> Int {
        min(max(value ?? defaultCount, countRange.lowerBound), countRange.upperBound)
    }

    /// The active tab index, clamped to the windows that exist.
    public static func clampedActiveIndex(_ value: Int?, count: Int) -> Int {
        min(max(value ?? defaultActiveIndex, 0), max(0, count - 1))
    }

    /// The first `count` demo windows (count is clamped to 1...8). Window IDs are 1-based, frames run
    /// left to right, and the most recently focused window is the last one.
    public static func windows(count: Int) -> [WindowSnapshot] {
        apps.prefix(clampedCount(count)).enumerated().map { index, app in
            WindowSnapshot(
                windowID: UInt32(index + 1),
                pid: -1,
                appKey: app.appKey,
                appName: app.name,
                title: app.title,
                frame: CGRect(x: 40 + CGFloat(index) * 170, y: 120 + CGFloat(index % 3) * 40, width: 700, height: 520),
                lastFocusedAt: Date(timeIntervalSince1970: 1_000 + Double(index) * 10)
            )
        }
    }

    /// The demo app behind an app key, if it is one.
    public static func app(forKey key: String) -> DemoApp? {
        apps.first { $0.appKey == key }
    }

    /// Window ID of the tab at `index` in the given demo windows, or nil when out of range.
    public static func windowID(at index: Int, in windows: [WindowSnapshot]) -> UInt32? {
        windows.indices.contains(index) ? windows[index].windowID : nil
    }
}
