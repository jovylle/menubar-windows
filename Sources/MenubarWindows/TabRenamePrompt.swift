// TabRenamePrompt.swift
// The "Rename Tab" dialog: one text field, prefilled with the tab's current label. Returns what was typed,
// or nil when the user cancels. An empty result means "reset"; AppDelegate decides what that does.
//
// Gotchas:
// - This is an accessory app and the strip never becomes key, so the app activates first. Without that,
//   the field does not get keyboard focus.
// - The caller shows the prompt after the context menu has closed (StripContentView dispatches it async).
//   A modal run inside the menu's tracking loop is fragile.
// - runModal blocks the run loop's default mode, so the 0.5s refresh does not run while the prompt is open.
// - NSAlert is a modal panel, below the strip's .popUpMenu level. It is placed on screen, away from the
//   menu bar, so the strip should not cover it.

import AppKit

enum TabRenamePrompt {
    /// The text the user entered (possibly empty), or nil when cancelled.
    static func ask(prefill: String) -> String? {
        AppActivation.bringToFront()
        let alert = NSAlert()
        alert.messageText = "Rename Tab"
        alert.informativeText = "The name replaces this tab's label only. Leave the field empty to show the label again."
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(string: prefill)
        field.frame = NSRect(x: 0, y: 0, width: 300, height: 24)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return field.stringValue
    }
}
