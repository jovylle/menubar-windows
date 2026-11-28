// TabLabel.swift
// What text a tab shows for a window, per the user's label mode. Pure, so the Settings preview and the
// real strip produce identical text.
//
// Gotchas:
// - Window titles can contain newlines and leading or trailing spaces; they are flattened to one line
//   before truncation.
// - A custom name (Rename Tab…) replaces the label in every mode except icon only, which stays empty by
//   design. The accessibility text keeps the real window title.

import Foundation

public enum TabLabelMode: String, CaseIterable, Identifiable, Sendable {
    case appName
    case windowTitle
    case appAndTitle
    case iconOnly

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .appName: return "App name"
        case .windowTitle: return "Window title"
        case .appAndTitle: return "App name and title"
        case .iconOnly: return "Icon only"
        }
    }
}

public enum TabLabel {
    /// Maximum characters before an ellipsis.
    public static let maximumLength = 22

    /// The visible label. Empty for `.iconOnly`.
    public static func text(appName: String, title: String, mode: TabLabelMode, customName: String? = nil) -> String {
        truncate(fullText(appName: appName, title: title, mode: mode, customName: customName), to: maximumLength)
    }

    /// The label before truncation. A custom name replaces it, except in icon-only mode.
    public static func fullText(appName: String, title: String, mode: TabLabelMode, customName: String? = nil) -> String {
        if mode == .iconOnly { return "" }
        if let customName, !customName.isEmpty { return customName }
        let oneLine = title
            .components(separatedBy: .newlines)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        let hasOwnTitle = !oneLine.isEmpty && oneLine != appName
        switch mode {
        case .appName:
            return appName
        case .windowTitle:
            return hasOwnTitle ? oneLine : appName
        case .appAndTitle:
            return hasOwnTitle ? "\(appName): \(oneLine)" : appName
        case .iconOnly:
            return ""
        }
    }

    /// What the rename prompt starts with: the custom name, else the untruncated label. Icon-only shows no
    /// label, so it starts from the accessibility text instead.
    public static func renamePrefill(appName: String, title: String, mode: TabLabelMode, customName: String?) -> String {
        if let customName, !customName.isEmpty { return customName }
        let full = fullText(appName: appName, title: title, mode: mode)
        return full.isEmpty ? accessibilityText(appName: appName, title: title) : full
    }

    /// Full, untruncated description used for tooltips and VoiceOver.
    public static func accessibilityText(appName: String, title: String) -> String {
        let oneLine = title
            .components(separatedBy: .newlines)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        return (oneLine.isEmpty || oneLine == appName) ? appName : "\(appName), \(oneLine)"
    }

    public static func truncate(_ text: String, to limit: Int) -> String {
        text.count > limit ? String(text.prefix(limit - 1)) + "…" : text
    }
}
