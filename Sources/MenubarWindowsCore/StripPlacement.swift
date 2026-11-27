// StripPlacement.swift
// Where the strip sits on one screen for the stored alignment, and where a Left span sits on a screen
// without a notch. Pure, so the real strip, the preview, --list and the tests agree.
//
// Gotchas: the picker's labels come from one global fact, whether any connected screen has a notch
// (`pickerShowsNotchLabels`), and they apply to every screen. With that fact the picker shows Left and
// Middle, so on a screen without a notch the stored center (and left) is Left and the stored right is
// Middle. Without it the picker shows Left, Middle and Right, one choice per stored value. On a notched
// screen Left hugs the Apple menu side (the first tab sits next to the Apple logo) and Middle sits against
// the notch. A Left span never slides left to keep its width: status icons only shorten its right end.

import CoreGraphics

public enum StripPlacement {
    /// Which edge of the strip's region the tabs sit against.
    public enum Edge: String, Equatable {
        case leading
        case center
        case trailing
    }

    /// The stored alignment, as Core sees it. The app maps its StripAlignment to this one to one.
    public enum Choice: String, Equatable {
        case left
        case center
        case right
    }

    /// The region a strip fills on one screen.
    public enum Region: Equatable {
        /// On a notched screen: everything between the Apple menu and the notch.
        case notch
        /// Left off a notch: starts after the Apple menu (see `leftSpan`) and is the strip width.
        case leftSpan
        /// Middle or Right off a notch: a block of the strip width centered in the bar.
        case centered
    }

    /// What a stored alignment does on one screen.
    public struct Placement: Equatable {
        public let region: Region
        /// The edge the tabs sit against. It anchors a narrower panel and aligns the tabs inside it.
        public let edge: Edge

        public init(region: Region, edge: Edge) {
            self.region = region
            self.edge = edge
        }
    }

    /// What a stored alignment does on one screen.
    /// - Parameters:
    ///   - choice: the stored alignment.
    ///   - pickerShowsNotchLabels: some connected screen has a notch, so the picker shows Left and Middle
    ///     for every screen. Left is stored as center (or left); Middle is stored as right.
    ///   - screenHasNotch: this screen has a notch. Its region is the bar up to the notch.
    public static func placement(for choice: Choice, pickerShowsNotchLabels: Bool, screenHasNotch: Bool) -> Placement {
        if screenHasNotch {
            return Placement(region: .notch, edge: choice == .right ? .trailing : .leading)
        }
        if pickerShowsNotchLabels {
            return choice == .right
                ? Placement(region: .centered, edge: .center)
                : Placement(region: .leftSpan, edge: .leading)
        }
        switch choice {
        case .left: return Placement(region: .leftSpan, edge: .leading)
        case .center: return Placement(region: .centered, edge: .center)
        case .right: return Placement(region: .centered, edge: .trailing)
        }
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
