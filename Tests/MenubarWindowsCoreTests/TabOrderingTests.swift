// TabOrderingTests.swift
// Swift Testing (ships with the Command Line Tools, works offline). Run with `swift test`.

import CoreGraphics
import Foundation
import Testing
@testable import MenubarWindowsCore

private func window(
    _ id: UInt32,
    _ app: String,
    x: CGFloat = 0,
    top: CGFloat = 800,
    focused: TimeInterval? = nil
) -> WindowSnapshot {
    WindowSnapshot(
        windowID: id,
        pid: Int32(app.hashValue & 0x7fff),
        appKey: "com.example.\(app.lowercased())",
        appName: app,
        title: "\(app) \(id)",
        frame: CGRect(x: x, y: top - 400, width: 600, height: 400),
        lastFocusedAt: focused.map { Date(timeIntervalSince1970: $0) }
    )
}

private func ids(_ list: [WindowSnapshot]) -> [UInt32] { list.map(\.windowID) }

@Suite("Automatic order")
struct AutomaticOrderTests {
    @Test func initialBatchIsAppNameThenWindowID() {
        let tracker = WindowOrderTracker()
        let result = tracker.ordered([window(9, "Zed"), window(3, "Notes"), window(1, "Zed")], mode: .automatic)
        #expect(ids(result) == [3, 1, 9])
    }

    @Test func clickingDoesNotReshuffle() {
        let tracker = WindowOrderTracker()
        let first = tracker.ordered([window(1, "A"), window(2, "B"), window(3, "C")], mode: .automatic)
        // Focus changes and the CG z-order flips; the order must not move.
        tracker.noteFocused(3)
        let second = tracker.ordered([window(3, "C"), window(1, "A"), window(2, "B")], mode: .automatic)
        #expect(ids(first) == ids(second))
    }

    @Test func newWindowGoesLast() {
        let tracker = WindowOrderTracker()
        _ = tracker.ordered([window(5, "B"), window(6, "C")], mode: .automatic)
        // Window 1 sorts first by ID and app name, but it is new, so it goes last.
        let result = tracker.ordered([window(1, "A"), window(5, "B"), window(6, "C")], mode: .automatic)
        #expect(ids(result) == [5, 6, 1])
    }

    @Test func disappearingWindowKeepsOthersStable() {
        let tracker = WindowOrderTracker()
        _ = tracker.ordered([window(1, "A"), window(2, "B"), window(3, "C")], mode: .automatic)
        let without = tracker.ordered([window(1, "A"), window(3, "C")], mode: .automatic)
        #expect(ids(without) == [1, 3])
    }

    @Test func briefAbsenceKeepsSlotUntilPruned() {
        let tracker = WindowOrderTracker()
        _ = tracker.ordered([window(1, "A"), window(2, "B")], mode: .automatic)
        _ = tracker.ordered([window(2, "B")], mode: .automatic)   // 1 off screen, still alive
        let back = tracker.ordered([window(2, "B"), window(1, "A")], mode: .automatic)
        #expect(ids(back) == [1, 2])

        tracker.prune(keeping: [2])                                // 1 closed for good
        let reopened = tracker.ordered([window(2, "B"), window(1, "A")], mode: .automatic)
        #expect(ids(reopened) == [2, 1])
    }
}

@Suite("Other modes")
struct OtherModeTests {
    @Test func recentFirst() {
        let tracker = WindowOrderTracker()
        let list = [window(1, "A"), window(2, "B"), window(3, "C")]
        _ = tracker.ordered(list, mode: .recentFirst)
        tracker.noteFocused(2, at: Date(timeIntervalSince1970: 100))
        tracker.noteFocused(3, at: Date(timeIntervalSince1970: 200))
        // 3 most recent, then 2, then never-focused 1 in automatic order.
        #expect(ids(tracker.ordered(list, mode: .recentFirst)) == [3, 2, 1])
        tracker.noteFocused(1, at: Date(timeIntervalSince1970: 300))
        #expect(ids(tracker.ordered(list, mode: .recentFirst)) == [1, 3, 2])
    }

    @Test func appNameIsCaseInsensitiveAndStableWithinApp() {
        let tracker = WindowOrderTracker()
        _ = tracker.ordered([window(7, "safari"), window(2, "Safari")], mode: .automatic)
        let result = tracker.ordered(
            [window(2, "Safari"), window(4, "Mail"), window(7, "safari"), window(1, "zed")],
            mode: .appName
        )
        #expect(result.first?.appName == "Mail")
        #expect(result.last?.appName == "zed")
    }

    @Test func leftToRight() {
        let list = [window(1, "A", x: 900), window(2, "B", x: 10), window(3, "C", x: 400)]
        let result = TabOrdering.order(list, mode: .leftToRight, firstSeen: [:])
        #expect(ids(result) == [2, 3, 1])
    }

    @Test func leftToRightTieBreaksByHigherWindow() {
        let list = [window(1, "A", x: 0, top: 500), window(2, "B", x: 0, top: 900)]
        #expect(ids(TabOrdering.order(list, mode: .leftToRight, firstSeen: [:])) == [2, 1])
    }

    @Test func pinnedFirstUsesPinOrderThenAutomatic() {
        let tracker = WindowOrderTracker()
        let list = [window(1, "A"), window(2, "B"), window(3, "C"), window(4, "C")]
        _ = tracker.ordered(list, mode: .automatic)
        let pins = ["com.example.c", "com.example.b"]
        #expect(ids(tracker.ordered(list, mode: .pinnedFirst, pinnedApps: pins)) == [3, 4, 2, 1])
    }

    @Test func pinnedFirstWithoutPinsEqualsAutomatic() {
        let tracker = WindowOrderTracker()
        let list = [window(5, "B"), window(1, "A")]
        let automatic = tracker.ordered(list, mode: .automatic)
        #expect(ids(tracker.ordered(list, mode: .pinnedFirst)) == ids(automatic))
    }

    @Test func pinnedNewWindowGoesLastWithinItsApp() {
        let tracker = WindowOrderTracker()
        _ = tracker.ordered([window(3, "C"), window(1, "A")], mode: .automatic)
        let result = tracker.ordered(
            [window(3, "C"), window(1, "A"), window(2, "C")],
            mode: .pinnedFirst,
            pinnedApps: ["com.example.c"]
        )
        #expect(ids(result) == [3, 2, 1])
    }

    @Test func everyModeIsDeterministic() {
        let list = [window(3, "C", x: 5), window(1, "A", x: 5), window(2, "B", x: 5)]
        for mode in TabOrderMode.allCases {
            let a = TabOrdering.order(list, mode: mode, firstSeen: [:])
            let b = TabOrdering.order(list.reversed(), mode: mode, firstSeen: [:])
            #expect(ids(a) == ids(b), "mode \(mode.rawValue)")
        }
    }
}

@Suite("Labels")
struct LabelTests {
    @Test func modes() {
        #expect(TabLabel.text(appName: "Notes", title: "Groceries", mode: .appName) == "Notes")
        #expect(TabLabel.text(appName: "Notes", title: "Groceries", mode: .windowTitle) == "Groceries")
        #expect(TabLabel.text(appName: "Notes", title: "Groceries", mode: .appAndTitle) == "Notes: Groceries")
        #expect(TabLabel.text(appName: "Notes", title: "Groceries", mode: .iconOnly) == "")
        #expect(TabLabel.text(appName: "Notes", title: "", mode: .windowTitle) == "Notes")
    }

    @Test func flattensAndTruncates() {
        let text = TabLabel.text(appName: "App", title: "line one\nline two is long", mode: .windowTitle)
        #expect(!text.contains("\n"))
        #expect(text.count == TabLabel.maximumLength)
        #expect(text.hasSuffix("…"))
    }
}
