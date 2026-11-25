// TabPalette.swift
// Fill and text colors of a tab per theme, appearance and state, plus the WCAG 2 contrast ratio used by
// the tests to keep every pair at 4.5:1 or more. Pure, so PillView and the tests share one table.
//
// Gotchas:
// - Colors are gray levels in sRGB with an alpha. The tab fill sits on top of a menu-material effect
//   view whose own color depends on the wallpaper, so the tests check the fill over the worst backdrop
//   (black in light mode, white in dark mode), not only over the usual material.
// - Minimized tabs are told apart by a dimmed icon, the tooltip and VoiceOver. Their label keeps full
//   contrast: a dimmed label fell to about 2.6:1 over the worst backdrop.
// - Pure black is opaque, so its backdrop does not matter. Its active tab has full-white text and the
//   others slightly dimmer text.

import Foundation

public struct Gray: Equatable, Sendable {
    /// sRGB gray level, 0 (black) to 1 (white).
    public let white: Double
    public let alpha: Double

    public init(_ white: Double, alpha: Double = 1) {
        self.white = white
        self.alpha = alpha
    }

    /// This color drawn over an opaque gray `backdrop` (simple sRGB alpha blending, as Core Animation does).
    public func over(_ backdrop: Double) -> Double {
        white * alpha + backdrop * (1 - alpha)
    }
}

public enum TabPalette {
    public struct Colors: Equatable, Sendable {
        public let fill: Gray
        public let text: Gray
    }

    /// Alpha of a minimized tab's icon.
    public static let minimizedIconAlpha: Double = 0.45

    /// - Parameters:
    ///   - pureBlack: the Pure black theme.
    ///   - light: the effective appearance is light (aqua).
    ///   - active: the tab of the focused window (or a +N tab holding it).
    ///   - activeFill: the active indicator includes the brighter fill.
    public static func colors(pureBlack: Bool, light: Bool, active: Bool, activeFill: Bool) -> Colors {
        if pureBlack {
            return Colors(fill: Gray(0), text: Gray(1, alpha: active ? 1 : 0.82))
        }
        let filled = active && activeFill
        if light {
            return Colors(fill: filled ? Gray(1) : Gray(0.9, alpha: 0.62), text: Gray(0.07))
        }
        return filled
            ? Colors(fill: Gray(0.96, alpha: 0.96), text: Gray(0.07))
            : Colors(fill: Gray(0, alpha: 0.55), text: Gray(1))
    }

    /// Worst-case backdrop behind the translucent fill for an appearance.
    public static func worstBackdrop(light: Bool) -> Double { light ? 0 : 1 }

    /// Typical menu-material backdrop for an appearance.
    public static func materialBackdrop(light: Bool) -> Double { light ? 0.93 : 0.2 }

    /// Contrast ratio of the label over its tab, with the fill drawn over `backdrop`.
    public static func contrast(_ colors: Colors, backdrop: Double) -> Double {
        let background = colors.fill.over(backdrop)
        let text = colors.text.over(background)
        return Contrast.ratio(text, background)
    }
}

public enum Contrast {
    /// WCAG 2 relative luminance of an sRGB gray level.
    public static func luminance(_ gray: Double) -> Double {
        gray <= 0.04045 ? gray / 12.92 : pow((gray + 0.055) / 1.055, 2.4)
    }

    /// WCAG 2 contrast ratio of two sRGB gray levels, 1 to 21.
    public static func ratio(_ a: Double, _ b: Double) -> Double {
        let la = luminance(a)
        let lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }
}
