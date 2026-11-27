// StripPlacementTests.swift
// Swift Testing. Left on a notched screen starts at the Apple menu side; Middle and Right keep their edges.

import Testing
@testable import MenubarWindowsCore

@Suite("Strip placement")
struct StripPlacementTests {
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

    @Test("Middle on a notched screen sits against the notch")
    func middleOnNotch() {
        #expect(StripPlacement.edge(rightChoice: true, onNotchedScreen: true) == .trailing)
    }
}
