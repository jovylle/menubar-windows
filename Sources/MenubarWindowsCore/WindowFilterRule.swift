// WindowFilterRule.swift
// Which windows get a tab, by size and AX subrole. Pure, so the helper-window rules are unit tested.
//
// Gotchas:
// - Some apps (Edge's Find bar, popovers, palettes) expose helper windows as real AX windows. With
//   "Ignore small helper windows" on, a window is dropped when the app reports an AX subrole other than
//   AXStandardWindow or AXDialog, or when either side is smaller than the configured size.
// - With it off, only the original floor applies: wider than 80 and taller than 40.
// - A missing or empty subrole is not a reason to drop a window: some apps (Zed, older Electron) report
//   none for their main windows.

import CoreGraphics

public enum WindowFilterRule {
    /// Windows at or below this size are always ignored.
    public static let minimumWidth: CGFloat = 80
    public static let minimumHeight: CGFloat = 40
    /// Subroles that count as real windows when the app reports one.
    public static let windowSubroles: Set<String> = ["AXStandardWindow", "AXDialog"]

    public static func passes(
        size: CGSize,
        subrole: String?,
        ignoreSmallWindows: Bool,
        smallWindowSize: CGFloat
    ) -> Bool {
        guard size.width > minimumWidth, size.height > minimumHeight else { return false }
        guard ignoreSmallWindows else { return true }
        if let subrole, !subrole.isEmpty, !windowSubroles.contains(subrole) { return false }
        return size.width >= smallWindowSize && size.height >= smallWindowSize
    }
}
