// TabOrderingTests.swift
// Tests for TabOrdering and WindowOrderTracker: every order mode, the manual order (drag to reorder), and
// pruning. Swift Testing (ships with the Command Line Tools, works offline). Run with `swift test`.
//
// Gotchas:
// - Manual order is keyed by window ID only, so these tests use fixed IDs. Real IDs change on restart,
//   which is why the manual order is memory only.

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

@Suite("Manual order")
struct ManualOrderTests {
    @Test func movePlacesItemAtTarget() {
        #expect(TabOrdering.move([1, 2, 3, 4], from: 0, to: 2) == [2, 3, 1, 4])
        #expect(TabOrdering.move([1, 2, 3, 4], from: 3, to: 0) == [4, 1, 2, 3])
        #expect(TabOrdering.move([1, 2, 3, 4], from: 2, to: 2) == [1, 2, 3, 4])
    }

    @Test func moveClampsTargetAndIgnoresBadSource() {
        #expect(TabOrdering.move([1, 2, 3], from: 0, to: 99) == [2, 3, 1])
        #expect(TabOrdering.move([1, 2, 3], from: 1, to: -4) == [2, 1, 3])
        #expect(TabOrdering.move([1, 2, 3], from: 7, to: 0) == [1, 2, 3])
        #expect(TabOrdering.move([], from: 0, to: 0) == [])
    }

    @Test func manualOrderFollowsStoredListAndNewWindowsGoLast() {
        let list = [window(1, "A"), window(2, "B"), window(3, "C"), window(9, "Z")]
        let result = TabOrdering.order(list, mode: .manual, firstSeen: [:], manualOrder: [3, 1, 2])
        #expect(ids(result) == [3, 1, 2, 9])
    }

    @Test func manualOrderIgnoresStaleIDs() {
        let list = [window(1, "A"), window(2, "B")]
        let result = TabOrdering.order(list, mode: .manual, firstSeen: [:], manualOrder: [7, 2, 8, 1])
        #expect(ids(result) == [2, 1])
    }

    @Test func manualWithoutStoredOrderIsAutomatic() {
        let tracker = WindowOrderTracker()
        let list = [window(5, "B"), window(1, "A"), window(3, "C")]
        let automatic = tracker.ordered(list, mode: .automatic)
        #expect(ids(tracker.ordered(list, mode: .manual)) == ids(automatic))
    }

    @Test func moveManualSeedsFromVisibleOrderThenMoves() {
        let tracker = WindowOrderTracker()
        let list = [window(1, "A"), window(2, "B"), window(3, "C")]
        let shown = ids(tracker.ordered(list, mode: .automatic))   // [1, 2, 3]
        tracker.resetManualOrder()
        tracker.moveManual(from: 0, to: 2, visible: shown)
        #expect(tracker.manualOrder == [2, 3, 1])
        #expect(ids(tracker.ordered(list, mode: .manual)) == [2, 3, 1])
    }

    @Test func moveManualKeepsOtherScreensRelativeOrder() {
        let tracker = WindowOrderTracker()
        tracker.moveManual(from: 0, to: 0, visible: [10, 11])   // seed: 10, 11
        tracker.moveManual(from: 1, to: 0, visible: [20, 21])   // another strip: 21, 20
        tracker.moveManual(from: 1, to: 0, visible: [10, 11])   // back here: 11, 10
        #expect(tracker.manualOrder == [11, 10, 21, 20])
    }

    @Test func newWindowAfterDragGoesLast() {
        let tracker = WindowOrderTracker()
        let list = [window(1, "A"), window(2, "B")]
        tracker.moveManual(from: 0, to: 1, visible: [1, 2])     // [2, 1]
        let result = tracker.ordered(list + [window(4, "D")], mode: .manual)
        #expect(ids(result) == [2, 1, 4])
    }

    @Test func closedWindowDropsOutOfManualOrderOnPrune() {
        let tracker = WindowOrderTracker()
        _ = tracker.ordered([window(1, "A"), window(2, "B"), window(3, "C")], mode: .automatic)
        tracker.moveManual(from: 0, to: 2, visible: [1, 2, 3])  // [2, 3, 1]
        tracker.prune(keeping: [1, 3])
        #expect(tracker.manualOrder == [3, 1])
        #expect(ids(tracker.ordered([window(1, "A"), window(3, "C")], mode: .manual)) == [3, 1])
    }

    @Test func resetClearsManualOrder() {
        let tracker = WindowOrderTracker()
        tracker.moveManual(from: 0, to: 1, visible: [1, 2])
        tracker.resetManualOrder()
        #expect(tracker.manualOrder.isEmpty)
    }
}
