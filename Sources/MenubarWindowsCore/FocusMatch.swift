// FocusMatch.swift
// Decides which tab shows as active. Pure, so the rules are unit tested.
//
// Gotchas:
// - The frontmost app's AXFocusedWindow is not always a tab. Edge's Find bar, popovers, palettes and
//   other helper windows can hold focus while the real window behind them stays the app's main window.
//   So when the focused window has no tab, the app's AXMainWindow is used instead.
// - AX calls time out (0.2s) on a busy app, Electron apps in particular. A timed-out lookup is not
//   "nothing is focused": the previous active tab of the same app is kept, so the highlight does not
//   flicker off for one refresh.
// - A window matched to its tab by bounds (when _AXUIElementGetWindow fails) has no AX window ID, so the
//   caller resolves focused and main windows to tab IDs itself (by ID or by AX element equality).

public enum FocusMatch {
    /// The tab ID to mark active, or nil when no tab of the frontmost app is focused.
    /// - Parameters:
    ///   - focused: tab ID of the frontmost app's AXFocusedWindow, nil when it has no tab.
    ///   - main: tab ID of the frontmost app's AXMainWindow, nil when it has no tab.
    ///   - lookupTimedOut: true when the AX lookups failed because the app did not answer in time.
    ///   - previous: the tab that was active on the last refresh, if it belongs to the same app.
    ///   - candidates: the frontmost app's current tab IDs.
    public static func activeWindow(
        focused: UInt32?,
        main: UInt32?,
        lookupTimedOut: Bool,
        previous: UInt32?,
        candidates: [UInt32]
    ) -> UInt32? {
        if let focused, candidates.contains(focused) { return focused }
        if let main, candidates.contains(main) { return main }
        if lookupTimedOut, let previous, candidates.contains(previous) { return previous }
        return nil
    }
}
