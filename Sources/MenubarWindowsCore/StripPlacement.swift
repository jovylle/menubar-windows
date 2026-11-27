// StripPlacement.swift
// Which edge of the strip's region a narrower strip sits against. Pure, so the real strip and the
// tests agree.
//
// Gotchas: on a notched screen the picker's "Left" choice (the center option there) hugs the Apple menu
// side, so the first tab sits next to the Apple logo. Centering it left a gap after the app menus. Off a
// notch, Left is its own choice (`leftChoice`) and the center option stays centered.

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
}
