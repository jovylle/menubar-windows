// StripPlacement.swift
// Which edge of the strip's region a narrower strip sits against. Pure, so the real strip and the
// tests agree.
//
// Gotchas: on a notched screen the picker's "Left" choice (the center option there) hugs the Apple menu
// side, so the first tab sits next to the Apple logo. Centering it left a gap after the app menus. Off a
// notch there is no "Left" choice, so the center option stays centered.

public enum StripPlacement {
    /// Where a strip narrower than its region sits.
    public enum Edge: String, Equatable {
        case leading
        case center
        case trailing
    }

    /// - Parameters:
    ///   - rightChoice: the "Right" option (on a notched screen, "Middle") pushes the strip to the end.
    ///   - onNotchedScreen: the region is the bar between the Apple menu and the notch.
    public static func edge(rightChoice: Bool, onNotchedScreen: Bool) -> Edge {
        if rightChoice { return .trailing }
        return onNotchedScreen ? .leading : .center
    }
}
