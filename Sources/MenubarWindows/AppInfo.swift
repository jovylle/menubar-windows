// AppInfo.swift
// The ONE place for the product's name, bundle identifier and tagline. scripts/app-info.sh reads these
// three lines, so a rename is a one-line change here (plus the Swift package and target names, which
// are internal and may stay as they are).
//
// Gotcha: keep each value on its own line in the exact `static let name = "value"` form; the shell
// script extracts them with sed.

import Foundation

enum AppInfo {
    static let displayName = "MenubarWindows"
    static let bundleIdentifier = "com.jovylle.menubarwindows"
    static let tagline = "Your windows, as tabs in the empty middle of the menu bar."

    /// CFBundleShortVersionString from the app bundle, or "dev" when run with `swift run`.
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    static var copyright: String {
        Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String
            ?? "All rights reserved."
    }

    /// True when running from a built .app bundle (needed for Launch at login).
    static var isBundled: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }
}
