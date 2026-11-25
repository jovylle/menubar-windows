// FocusPaletteFilterTests.swift
// Active-tab matching, tab color contrast (WCAG 2, 4.5:1) and the helper-window filter.

import CoreGraphics
import Foundation
import Testing
@testable import MenubarWindowsCore

@Suite("Active tab")
struct FocusMatchTests {
    @Test func focusedWindowWins() {
        #expect(FocusMatch.activeWindow(focused: 2, main: 1, lookupTimedOut: false, previous: nil, candidates: [1, 2]) == 2)
    }

    @Test func helperWindowFocusedFallsBackToMainWindow() {
        // Edge's Find bar has focus: it has no tab, the browser window behind it is the main window.
        #expect(FocusMatch.activeWindow(focused: nil, main: 1, lookupTimedOut: false, previous: nil, candidates: [1, 2]) == 1)
    }

    @Test func focusedWindowWithoutTabAndNoMainWindowMeansNoActiveTab() {
        #expect(FocusMatch.activeWindow(focused: nil, main: nil, lookupTimedOut: false, previous: 1, candidates: [1, 2]) == nil)
    }

    @Test func timeoutKeepsPreviousActiveTab() {
        #expect(FocusMatch.activeWindow(focused: nil, main: nil, lookupTimedOut: true, previous: 2, candidates: [1, 2]) == 2)
    }

    @Test func timeoutDoesNotKeepAClosedWindow() {
        #expect(FocusMatch.activeWindow(focused: nil, main: nil, lookupTimedOut: true, previous: 3, candidates: [1, 2]) == nil)
    }

    @Test func idsOutsideTheCandidatesAreIgnored() {
        #expect(FocusMatch.activeWindow(focused: 9, main: 8, lookupTimedOut: false, previous: nil, candidates: [1]) == nil)
    }
}

@Suite("Tab contrast")
struct TabPaletteTests {
    /// Every theme, appearance and state a tab can be drawn in. Minimized, +N and the permission pill
    /// use the inactive or active colors (minimized only dims the icon).
    static let cases: [(name: String, pureBlack: Bool, light: Bool, active: Bool, activeFill: Bool)] = [
        ("light inactive", false, true, false, true),
        ("light active fill", false, true, true, true),
        ("light active underline", false, true, true, false),
        ("dark inactive", false, false, false, true),
        ("dark active fill", false, false, true, true),
        ("dark active underline", false, false, true, false),
        ("black on light inactive", true, true, false, true),
        ("black on light active", true, true, true, true),
        ("black on dark inactive", true, false, false, true),
        ("black on dark active", true, false, true, true)
    ]

    @Test func everyLabelIsAtLeast4_5To1OverTheWorstBackdrop() {
        for item in Self.cases {
            let colors = TabPalette.colors(pureBlack: item.pureBlack, light: item.light, active: item.active, activeFill: item.activeFill)
            for backdrop in [TabPalette.worstBackdrop(light: item.light), TabPalette.materialBackdrop(light: item.light)] {
                let ratio = TabPalette.contrast(colors, backdrop: backdrop)
                #expect(ratio >= 4.5, "\(item.name) over \(backdrop): \(ratio)")
            }
        }
    }

    @Test func activeTabStandsOutFromInactive() {
        for light in [true, false] {
            let inactive = TabPalette.colors(pureBlack: false, light: light, active: false, activeFill: true)
            let active = TabPalette.colors(pureBlack: false, light: light, active: true, activeFill: true)
            #expect(active.fill != inactive.fill)
        }
        let black = TabPalette.colors(pureBlack: true, light: false, active: false, activeFill: true)
        let blackActive = TabPalette.colors(pureBlack: true, light: false, active: true, activeFill: true)
        #expect(blackActive.text.alpha > black.text.alpha)
    }

    @Test func wcagReferenceValues() {
        #expect(abs(Contrast.ratio(0, 1) - 21) < 0.001)
        #expect(abs(Contrast.ratio(0.5, 0.5) - 1) < 0.001)
        // #767676 on white is the classic 4.54:1 pair.
        #expect(abs(Contrast.ratio(118.0 / 255, 1) - 4.54) < 0.01)
    }
}

@Suite("Helper window filter")
struct WindowFilterRuleTests {
    private func passes(_ width: CGFloat, _ height: CGFloat, _ subrole: String?, ignore: Bool = true) -> Bool {
        WindowFilterRule.passes(size: CGSize(width: width, height: height), subrole: subrole,
                                ignoreSmallWindows: ignore, smallWindowSize: 100)
    }

    @Test func standardWindowsAndDialogsPass() {
        #expect(passes(800, 600, "AXStandardWindow"))
        #expect(passes(400, 200, "AXDialog"))
    }

    @Test func missingSubroleIsKept() {
        #expect(passes(800, 600, nil))
        #expect(passes(800, 600, ""))
    }

    @Test func edgeFindBarIsDropped() {
        // A wide, short strip, and a non-standard subrole when the app reports one.
        #expect(!passes(420, 52, "AXStandardWindow"))
        #expect(!passes(420, 300, "AXFloatingWindow"))
        #expect(!passes(420, 300, "AXSystemDialog"))
        #expect(!passes(420, 300, "AXUnknown"))
    }

    @Test func offKeepsHelpersAboveTheFloor() {
        #expect(passes(420, 52, "AXFloatingWindow", ignore: false))
        #expect(!passes(80, 300, "AXStandardWindow", ignore: false))
        #expect(!passes(300, 40, "AXStandardWindow", ignore: false))
    }
}

@Suite("Label edge cases")
struct LabelEdgeCaseTests {
    @Test func emptyAndWhitespaceTitlesShowTheAppName() {
        for title in ["", "   ", "\n", "\t"] {
            #expect(TabLabel.text(appName: "Zed", title: title, mode: .appAndTitle) == "Zed", "\(title.debugDescription)")
            #expect(TabLabel.text(appName: "Zed", title: title, mode: .windowTitle) == "Zed")
            #expect(TabLabel.accessibilityText(appName: "Zed", title: title) == "Zed")
        }
    }

    @Test func veryLongTitleIsCutToTheLimit() {
        let label = TabLabel.text(appName: "Edge", title: String(repeating: "x", count: 5000), mode: .windowTitle)
        #expect(label.count == TabLabel.maximumLength)
        #expect(label.hasSuffix("…"))
    }

    @Test func emojiAreNotSplit() {
        let label = TabLabel.text(appName: "A", title: String(repeating: "👩‍👩‍👧", count: 30), mode: .windowTitle)
        #expect(label.count == TabLabel.maximumLength)
    }
}
