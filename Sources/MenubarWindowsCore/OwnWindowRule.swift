// OwnWindowRule.swift
// Which of this app's own windows get a tab. Only the Settings window: the strip panel, the onboarding
// window and the demo backdrop are never tabs. Pure, so the rule is unit tested.
//
// Gotchas:
// - The window is identified by its NSWindow identifier, not its title. Titles are localized and can change.
// - Own windows are read in-process (NSApp.windows), never through AX: AX calls to our own process from
//   the main thread can stall until they time out.
// - The strip panel is on a popUpMenu-level layer, so the layer-0 check already drops it. This rule is a
//   second guard: a window needs the exact identifier to be listed.

public enum OwnWindowRule {
    /// Identifier set on the Settings window (SettingsWindowController).
    public static let settingsIdentifier = "mw.settings"

    public static func isTabWindow(identifier: String?) -> Bool {
        identifier == settingsIdentifier
    }
}
