// StripFillTests.swift
// Swift Testing. The strip takes its whole region from three tabs, and equal tabs then ignore the cap.

import CoreGraphics
import Testing
@testable import MenubarWindowsCore

@Suite("Strip fill")
struct StripFillTests {
    @Test("fills from three tabs")
    func threshold() {
        #expect(!StripFill.fillsRegion(tabCount: 2))
        #expect(StripFill.fillsRegion(tabCount: 3))
        #expect(StripFill.fillsRegion(tabCount: 8))
    }

    @Test("a filling strip ignores the widest tab cap")
    func ignoresCap() {
        let width = StripFill.equalTabWidth(
            available: 900, reserved: 0, gap: 0, count: 3, maximum: 220, minimum: 44, fills: true)
        #expect(width == 300)
    }

    @Test("without the fill the cap applies")
    func appliesCap() {
        let width = StripFill.equalTabWidth(
            available: 900, reserved: 0, gap: 0, count: 2, maximum: 220, minimum: 44, fills: false)
        #expect(width == 220)
    }

    @Test("the overflow tab and the gaps come off the share")
    func reservesOverflow() {
        let width = StripFill.equalTabWidth(
            available: 700, reserved: 61, gap: 1, count: 3, maximum: 220, minimum: 44, fills: true)
        #expect(width == 212)
    }

    @Test("never narrower than the minimum")
    func minimum() {
        let width = StripFill.equalTabWidth(
            available: 100, reserved: 0, gap: 0, count: 8, maximum: 220, minimum: 44, fills: true)
        #expect(width == 44)
    }
}
