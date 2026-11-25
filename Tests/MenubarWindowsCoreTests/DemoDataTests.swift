// DemoDataTests.swift
// Demo mode's invented windows: count and index clamping, stable IDs and names, and that every tab
// order mode gives a defined order over them.

import Foundation
import Testing
@testable import MenubarWindowsCore

@Suite("Demo data")
struct DemoDataTests {
    @Test func defaultIsSixWindowsInListOrder() {
        let windows = DemoData.windows(count: DemoData.defaultCount)
        #expect(windows.map(\.appName) == ["Draftpad", "Shellbox", "Mockups", "Planner", "Pagefold", "Statline"])
        #expect(windows.map(\.windowID) == [1, 2, 3, 4, 5, 6])
        #expect(windows.first?.title == "Launch notes")
    }

    @Test func countIsClampedToOneThroughEight() {
        #expect(DemoData.windows(count: 0).count == 1)
        #expect(DemoData.windows(count: -3).count == 1)
        #expect(DemoData.windows(count: 3).count == 3)
        #expect(DemoData.windows(count: 99).count == 8)
        #expect(DemoData.clampedCount(nil) == 6)
    }

    @Test func activeIndexIsClampedToTheWindowsThatExist() {
        #expect(DemoData.clampedActiveIndex(nil, count: 6) == 1)
        #expect(DemoData.clampedActiveIndex(-1, count: 6) == 0)
        #expect(DemoData.clampedActiveIndex(10, count: 3) == 2)
        #expect(DemoData.clampedActiveIndex(1, count: 1) == 0)
    }

    @Test func windowIDLookupIsBoundsChecked() {
        let windows = DemoData.windows(count: 3)
        #expect(DemoData.windowID(at: 2, in: windows) == 3)
        #expect(DemoData.windowID(at: 3, in: windows) == nil)
        #expect(DemoData.windowID(at: -1, in: windows) == nil)
    }

    @Test func namesAndKeysAreUniqueAndInvented() {
        let apps = DemoData.apps
        #expect(Set(apps.map(\.name)).count == apps.count)
        #expect(Set(apps.map(\.appKey)).count == apps.count)
        #expect(apps.allSatisfy { $0.appKey.hasPrefix("demo.") && $0.letter.count == 1 })
        #expect(DemoData.app(forKey: "demo.planner")?.name == "Planner")
        #expect(DemoData.app(forKey: "com.example.real") == nil)
        #expect(DemoData.displayNames == ["Built-in Display", "External Display"])
    }

    @Test func everyOrderModeGivesAFullDefinedOrder() {
        let windows = DemoData.windows(count: 6)
        let firstSeen = Dictionary(uniqueKeysWithValues: windows.enumerated().map { ($1.windowID, $0) })
        for mode in TabOrderMode.allCases {
            let ordered = TabOrdering.order(windows, mode: mode, firstSeen: firstSeen, pinnedApps: ["demo.planner"])
            #expect(Set(ordered.map(\.windowID)) == Set(windows.map(\.windowID)), "mode \(mode.rawValue)")
        }
        let recent = TabOrdering.order(windows, mode: .recentFirst, firstSeen: firstSeen, pinnedApps: [])
        #expect(recent.first?.appName == "Statline")
        let byName = TabOrdering.order(windows, mode: .appName, firstSeen: firstSeen, pinnedApps: [])
        #expect(byName.map(\.appName) == ["Draftpad", "Mockups", "Pagefold", "Planner", "Shellbox", "Statline"])
        let pinned = TabOrdering.order(windows, mode: .pinnedFirst, firstSeen: firstSeen, pinnedApps: ["demo.planner"])
        #expect(pinned.first?.appName == "Planner")
        let automatic = TabOrdering.order(windows, mode: .automatic, firstSeen: firstSeen, pinnedApps: [])
        #expect(automatic.map(\.windowID) == [1, 2, 3, 4, 5, 6])
    }

    @Test func automaticOrderFollowsTheDemoListWhenFedOneAtATime() {
        // AppDelegate feeds the tracker one window at a time so a same-refresh batch is not sorted by name.
        let tracker = WindowOrderTracker()
        let windows = DemoData.windows(count: 6)
        for window in windows { tracker.observe([window]) }
        #expect(tracker.ordered(windows, mode: .automatic).map(\.windowID) == [1, 2, 3, 4, 5, 6])
    }
}
