// FullScreenRule tests: a full-screen window hides the strip only on the display that holds it.

import CoreGraphics
import Testing
@testable import MenubarWindowsCore

@Suite("Full-screen strip hiding")
struct FullScreenRuleTests {
    // Two displays side by side, Cocoa coordinates. The left one is the full-screen display.
    private let leftScreen = CGRect(x: 0, y: 0, width: 1000, height: 800)
    private let rightScreen = CGRect(x: 1000, y: 0, width: 1000, height: 800)

    @Test func noFullScreenWindowKeepsEveryStrip() {
        #expect(!FullScreenRule.hidesStrip(screenFrame: leftScreen, fullScreenFrames: []))
        #expect(!FullScreenRule.hidesStrip(screenFrame: rightScreen, fullScreenFrames: []))
    }

    @Test func fullScreenWindowHidesOnlyItsOwnDisplay() {
        let full = [leftScreen]
        #expect(FullScreenRule.hidesStrip(screenFrame: leftScreen, fullScreenFrames: full))
        #expect(!FullScreenRule.hidesStrip(screenFrame: rightScreen, fullScreenFrames: full))
    }

    @Test func fullScreenOnTheOtherDisplayLeavesThisOneAlone() {
        let full = [rightScreen]
        #expect(!FullScreenRule.hidesStrip(screenFrame: leftScreen, fullScreenFrames: full))
        #expect(FullScreenRule.hidesStrip(screenFrame: rightScreen, fullScreenFrames: full))
    }

    @Test func displayLeftOfThePrimaryWithNegativeOrigin() {
        let leftOfPrimary = CGRect(x: -1200, y: 0, width: 1200, height: 900)
        let full = [leftOfPrimary]
        #expect(FullScreenRule.hidesStrip(screenFrame: leftOfPrimary, fullScreenFrames: full))
        #expect(!FullScreenRule.hidesStrip(screenFrame: leftScreen, fullScreenFrames: full))
    }

    @Test func centerDecidesWhichScreenAWindowBelongsTo() {
        // Mostly on the right display, but its center sits on the right side of the boundary.
        let straddling = CGRect(x: 800, y: 0, width: 600, height: 800)
        #expect(FullScreenRule.hidesStrip(screenFrame: rightScreen, fullScreenFrames: [straddling]))
        #expect(!FullScreenRule.hidesStrip(screenFrame: leftScreen, fullScreenFrames: [straddling]))
    }

    @Test func fullScreenWindowsOnBothDisplaysHideBoth() {
        let full = [leftScreen, rightScreen]
        #expect(FullScreenRule.hidesStrip(screenFrame: leftScreen, fullScreenFrames: full))
        #expect(FullScreenRule.hidesStrip(screenFrame: rightScreen, fullScreenFrames: full))
    }

    @Test func unknownFrameHidesEveryScreen() {
        let unknown: [CGRect?] = [nil]
        #expect(FullScreenRule.hidesStrip(screenFrame: leftScreen, fullScreenFrames: unknown))
        #expect(FullScreenRule.hidesStrip(screenFrame: rightScreen, fullScreenFrames: unknown))
    }

    @Test func knownFrameOnOtherDisplayStillLeavesThisOneAlone() {
        let frames: [CGRect?] = [rightScreen]
        #expect(!FullScreenRule.hidesStrip(screenFrame: leftScreen, fullScreenFrames: frames))
    }
}
