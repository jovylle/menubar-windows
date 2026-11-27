// StripPlacement.swift
// Which edge of the strip's region a narrower strip sits against, and where a Left strip spans on a
// screen without a notch. Pure, so the real strip and the tests agree.
//
// Gotchas: on a notched screen the picker's "Left" choice (the center option there) hugs the Apple menu
// side, so the first tab sits next to the Apple logo. Centering it left a gap after the app menus. Off a
// notch, Left is its own choice (`leftChoice`) and the center option stays centered. A Left span never
// slides left to keep its width: status icons only shorten its right end.

import CoreGraphics

public enum StripPlacement {
    /// Where a strip narrower than its region sits.
    public enum Edge: String, Equatable {
        case leading
        case center
        case trailing
    }

    /// - Parameters:
    ///   - leftChoice: the "Left" option, which exists only off a notch, starts the strip at the leading edge.
    ///   - rightChoice: the "Right" option (on a notched screen, "Middle") pushes the strip to the end.
    ///   - onNotchedScreen: the region is the bar between the Apple menu and the notch.
    public static func edge(rightChoice: Bool, onNotchedScreen: Bool, leftChoice: Bool = false) -> Edge {
        if leftChoice { return .leading }
        if rightChoice { return .trailing }
        return onNotchedScreen ? .leading : .center
    }

    /// The span of a Left strip on a screen without a notch (Cocoa x). It starts next to the Apple menu, or
    /// at the screen edge when covering it, and is `width` wide. Status icons only shorten its right end.
    /// - Parameters:
    ///   - screenMinX: left edge of the screen.
    ///   - width: the strip width setting (the maximum in Automatic width mode).
    ///   - appleMenuInset: gap from the screen edge that keeps the Apple menu clear.
    ///   - coverAppleMenu: start at the screen edge, over the Apple menu.
    ///   - statusMinX: left edge of the leftmost status icon, or nil when there is none.
    ///   - statusGap: space kept between the strip and the status icons.
    /// - Returns: the left and right edges. The caller hides the strip when too little room is left.
    public static func leftSpan(
        screenMinX: CGFloat,
        width: CGFloat,
        appleMenuInset: CGFloat,
        coverAppleMenu: Bool,
        statusMinX: CGFloat?,
        statusGap: CGFloat
    ) -> (lo: CGFloat, hi: CGFloat) {
        let lo = screenMinX + (coverAppleMenu ? 0 : appleMenuInset)
        var hi = lo + width
        if let statusMinX = statusMinX {
            hi = min(hi, statusMinX - statusGap)
        }
        return (lo, hi)
    }
}
