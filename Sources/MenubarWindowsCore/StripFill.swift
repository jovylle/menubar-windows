// StripFill.swift
// When the strip fills its whole region and how wide each equal tab is. Pure, so the real strip and
// the tests agree.
//
// Gotchas: the "+N" overflow tab keeps its natural width, so it is reserved before the share is split.
// With the fill on there is no widest-tab cap: the tabs must reach both ends of the region.

import CoreGraphics

public enum StripFill {
    /// From this many window tabs the strip takes its whole region by default.
    public static let minimumTabs = 3

    public static func fillsRegion(tabCount: Int) -> Bool {
        tabCount >= minimumTabs
    }

    /// Width of one equal tab.
    /// - Parameters:
    ///   - available: width of the region.
    ///   - reserved: width kept for the "+N" tab and the gap before it (0 when there is none).
    ///   - gap: space between tabs (negative when square tabs overlap).
    ///   - count: number of window tabs.
    ///   - maximum: widest allowed tab. Ignored when `fills` is true.
    ///   - minimum: narrowest allowed tab.
    ///   - fills: whether the tabs must use the whole region.
    public static func equalTabWidth(
        available: CGFloat,
        reserved: CGFloat,
        gap: CGFloat,
        count: Int,
        maximum: CGFloat,
        minimum: CGFloat,
        fills: Bool
    ) -> CGFloat {
        guard count > 0 else { return minimum }
        let share = ((available - reserved - gap * CGFloat(count - 1)) / CGFloat(count)).rounded(.down)
        return max(minimum, fills ? share : min(maximum, share))
    }
}
