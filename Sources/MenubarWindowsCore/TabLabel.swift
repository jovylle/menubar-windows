// TabLabel.swift
// What text a tab shows for a window, per the user's label mode. Pure, so the Settings preview and the
// real strip produce identical text.
//
// Gotcha: window titles can contain newlines and leading or trailing spaces; they are flattened to one
// line before truncation.

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
    public static func text(appName: String, title: String, mode: TabLabelMode) -> String {
        let oneLine = title
            .components(separatedBy: .newlines)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        let hasOwnTitle = !oneLine.isEmpty && oneLine != appName
        let full: String
        switch mode {
        case .appName:
            full = appName
        case .windowTitle:
            full = hasOwnTitle ? oneLine : appName
        case .appAndTitle:
            full = hasOwnTitle ? "\(appName): \(oneLine)" : appName
        case .iconOnly:
            return ""
        }
        return truncate(full, to: maximumLength)
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
