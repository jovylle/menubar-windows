// StripPlacementTests.swift
// Swift Testing. The stored alignment maps to one placement per screen: Left starts after the Apple menu
// on every screen where the picker says Left, and Middle and Right keep their edges. The Left span off a
// notch starts after the Apple menu (or at the edge when covering it), is clipped only on its right by the
// status icons, and never slides left.

import CoreGraphics
import Testing
@testable import MenubarWindowsCore

@Suite("Strip placement")
struct StripPlacementTests {
    typealias Placement = StripPlacement.Placement

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

    @Test("every stored alignment, picker labels and screen notch: region and edge")
    func placementTable() {
        // (stored, picker shows notch labels, screen has a notch) -> (region, edge)
        let rows: [(StripPlacement.Choice, Bool, Bool, StripPlacement.Region, StripPlacement.Edge)] = [
            // No notch on any screen: the picker shows Left, Middle and Right.
            (.left, false, false, .leftSpan, .leading),
            (.center, false, false, .centered, .center),
            (.right, false, false, .centered, .trailing),
            // A notched screen is connected, so the picker shows Left and Middle. External screen, no notch.
            (.left, true, false, .leftSpan, .leading),
            (.center, true, false, .leftSpan, .leading),
            (.right, true, false, .centered, .center),
            // The notched screen itself: unchanged. Left hugs the Apple menu, Middle sits against the notch.
            (.left, true, true, .notch, .leading),
            (.center, true, true, .notch, .leading),
            (.right, true, true, .notch, .trailing),
            // A notched screen always uses the notch region, whatever the picker flag says.
            (.left, false, true, .notch, .leading),
            (.center, false, true, .notch, .leading),
            (.right, false, true, .notch, .trailing),
        ]
        for (choice, picker, notch, region, edge) in rows {
            let placement = StripPlacement.placement(for: choice, pickerShowsNotchLabels: picker, screenHasNotch: notch)
            #expect(placement == Placement(region: region, edge: edge),
                    "stored \(choice.rawValue), picker notch labels \(picker), screen notch \(notch)")
        }
    }

    @Test("stored center with a notched screen connected: the external screen's Left starts after the Apple menu")
    func centerLeftOnExternalWithNotchedPicker() {
        let placement = StripPlacement.placement(for: .center, pickerShowsNotchLabels: true, screenHasNotch: false)
        #expect(placement.region == .leftSpan)
        #expect(placement.edge == .leading)
        #expect(leftSpan().lo == 42)
    }

    @Test("stored center with a notched screen connected: covering the Apple menu starts at the edge")
    func centerLeftCoversOnExternalWithNotchedPicker() {
        let placement = StripPlacement.placement(for: .center, pickerShowsNotchLabels: true, screenHasNotch: false)
        #expect(placement.region == .leftSpan)
        #expect(leftSpan(cover: true).lo == 0)
    }

    @Test("stored right with a notched screen connected: the external screen's Middle is centered")
    func rightMiddleOnExternalWithNotchedPicker() {
        let placement = StripPlacement.placement(for: .right, pickerShowsNotchLabels: true, screenHasNotch: false)
        #expect(placement == Placement(region: .centered, edge: .center))
    }

    @Test("Left on a notched screen hugs the leading edge")
    func leftOnNotch() {
        let placement = StripPlacement.placement(for: .center, pickerShowsNotchLabels: true, screenHasNotch: true)
        #expect(placement == Placement(region: .notch, edge: .leading))
    }

    @Test("Middle on a notched screen sits against the notch")
    func middleOnNotch() {
        let placement = StripPlacement.placement(for: .right, pickerShowsNotchLabels: true, screenHasNotch: true)
        #expect(placement == Placement(region: .notch, edge: .trailing))
    }

    @Test("Middle on a screen without a notch and no notch anywhere stays centered")
    func middleWithoutNotch() {
        let placement = StripPlacement.placement(for: .center, pickerShowsNotchLabels: false, screenHasNotch: false)
        #expect(placement == Placement(region: .centered, edge: .center))
    }

    @Test("Right on a screen without a notch and no notch anywhere goes to the trailing edge")
    func rightWithoutNotch() {
        let placement = StripPlacement.placement(for: .right, pickerShowsNotchLabels: false, screenHasNotch: false)
        #expect(placement == Placement(region: .centered, edge: .trailing))
    }

    @Test("Left on a screen without a notch and no notch anywhere hugs the leading edge")
    func leftWithoutNotch() {
        let placement = StripPlacement.placement(for: .left, pickerShowsNotchLabels: false, screenHasNotch: false)
        #expect(placement == Placement(region: .leftSpan, edge: .leading))
    }
}
