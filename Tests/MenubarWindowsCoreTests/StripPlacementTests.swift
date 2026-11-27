// StripPlacementTests.swift
// Swift Testing. Left hugs the Apple menu side on every screen; Middle and Right keep their edges. The Left
// span off a notch starts after the Apple menu (or at the edge when covering it), is clipped only on its
// right by the status icons, and never slides left.

import CoreGraphics
import Testing
@testable import MenubarWindowsCore

@Suite("Strip placement")
struct StripPlacementTests {
    /// The Left span on a 1920 pt screen starting at x 0, with the usual 42 pt Apple menu inset and 12 pt gap.
    private func leftSpan(width: CGFloat = 560, cover: Bool = false, statusMinX: CGFloat? = nil,
                          screenMinX: CGFloat = 0) -> (lo: CGFloat, hi: CGFloat) {
        StripPlacement.leftSpan(
            screenMinX: screenMinX, width: width, appleMenuInset: 42,
            coverAppleMenu: cover, statusMinX: statusMinX, statusGap: 12)
    }

    @Test("Left off a notch starts after the Apple menu and is the strip width")
    func leftSpanStartsAfterAppleMenu() {
        let span = leftSpan()
        #expect(span.lo == 42)
        #expect(span.hi == 602)
    }

    @Test("Cover the Apple menu starts Left at the screen edge")
    func leftSpanCoversAppleMenu() {
        let span = leftSpan(cover: true)
        #expect(span.lo == 0)
        #expect(span.hi == 560)
    }

    @Test("Left uses the display's own left edge on a second screen")
    func leftSpanOnSecondScreen() {
        let span = leftSpan(screenMinX: 1920)
        #expect(span.lo == 1962)
        #expect(span.hi == 2522)
    }

    @Test("status icons far to the right leave the width alone")
    func leftSpanFarStatusIcons() {
        let span = leftSpan(statusMinX: 1500)
        #expect(span.hi == 602)
    }

    @Test("status icons clip the right end of Left")
    func leftSpanClipsRightEnd() {
        let span = leftSpan(statusMinX: 500)
        #expect(span.hi == 488)
    }

    @Test("Left never slides left to keep its width")
    func leftSpanNeverSlides() {
        let span = leftSpan(statusMinX: 500)
        #expect(span.lo == 42)
        let covered = leftSpan(cover: true, statusMinX: 300)
        #expect(covered.lo == 0)
        #expect(covered.hi == 288)
    }

    @Test("a narrow leftover span is returned as is, for the caller to hide")
    func leftSpanNarrowScreen() {
        // Status icons at 114 leave 114 - 12 = 102 as the right end, so the span is 102 - 42 = 60 pt wide.
        let span = leftSpan(statusMinX: 114)
        #expect(span.lo == 42)
        #expect(span.hi - span.lo == 60)
        #expect(span.hi - span.lo < 120)
    }

    @Test("Left on a notched screen hugs the leading edge")
    func leftOnNotch() {
        #expect(StripPlacement.edge(rightChoice: false, onNotchedScreen: true) == .leading)
    }

    @Test("Middle on a screen without a notch stays centered")
    func middleWithoutNotch() {
        #expect(StripPlacement.edge(rightChoice: false, onNotchedScreen: false) == .center)
    }

    @Test("Right on a screen without a notch goes to the trailing edge")
    func rightWithoutNotch() {
        #expect(StripPlacement.edge(rightChoice: true, onNotchedScreen: false) == .trailing)
    }

    @Test("Left on a screen without a notch hugs the leading edge")
    func leftWithoutNotch() {
        #expect(StripPlacement.edge(rightChoice: false, onNotchedScreen: false, leftChoice: true) == .leading)
    }

    @Test("Middle on a notched screen sits against the notch")
    func middleOnNotch() {
        #expect(StripPlacement.edge(rightChoice: true, onNotchedScreen: true) == .trailing)
    }
}
