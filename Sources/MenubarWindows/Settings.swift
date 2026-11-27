// Settings.swift
// Typed, UserDefaults-backed settings. `Settings.shared` is an ObservableObject: SwiftUI binds to it
// directly, and AppDelegate subscribes to `didChange` to re-render the strips live, without a restart.
//
// Gotchas:
// - Every property persists in its didSet (didSet does not run during init, so loading never writes).
//   Keys are prefixed with "mw.". Any key can be overridden for one run with a launch argument, for
//   example `-mw.hasCompletedOnboarding YES`.
// - The defaults domain is the bundle identifier for the .app, but the executable name for a bare
//   `swift run` binary, so the two keep separate settings.
// - objectWillChange fires BEFORE the value changes. `didChange` is debounced onto the next main-loop turn
//   so subscribers read the new value.
// - Displays are identified by their CoreGraphics display UUID, which survives reboots and
//   reconnects. NSScreen order and names are not stable enough.
// - The custom accent color is stored as sRGB components; NSColor itself is not plist-safe.
// - In demo mode `shared` reads and writes a separate, wiped suite (see DemoMode).
// - Defaults are only in `Defaults`. `isDefault`, `reset` and `resetToDefaults` all read from it, so a
//   new setting needs one case in each switch, plus one entry in `SettingID`. The compiler enforces the
//   switches. Reset assigns the published properties, so it goes through the same save and `didChange`
//   path as a manual change. It never touches pinned apps or the manual drag order.

import AppKit
import Combine
import MenubarWindowsCore

enum TabStyle: String, CaseIterable, Identifiable {
    case square
    case rounded
    var id: String { rawValue }
    var title: String {
        switch self {
        case .square: return "Square, flush with the top"
        case .rounded: return "Rounded"
        }
    }
}

enum ColorTheme: String, CaseIterable, Identifiable {
    case system
    case black
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return "Match the system (light or dark)"
        case .black: return "Pure black, in light and dark mode"
        }
    }
}

enum ActiveIndicator: String, CaseIterable, Identifiable {
    case underline
    case brighterFill
    case both
    var id: String { rawValue }
    var title: String {
        switch self {
        case .underline: return "Underline"
        case .brighterFill: return "Brighter fill"
        case .both: return "Both"
        }
    }
    var showsUnderline: Bool { self != .brighterFill }
    var showsFill: Bool { self != .underline }
}

enum StripWidthMode: String, CaseIterable, Identifiable {
    case automatic
    case fixed
    var id: String { rawValue }
    var title: String {
        switch self {
        case .automatic: return "Automatic (fit the tabs)"
        case .fixed: return "Fixed width"
        }
    }
}

enum StripAlignment: String, CaseIterable, Identifiable {
    /// Only offered off a notch. On a notched screen the center option is already called Left.
    case left
    case center
    case right
    var id: String { rawValue }
    var title: String { title(onNotchedScreen: false) }

    /// The options the picker offers: a notched screen has Left (center) and Middle (right); others have
    /// Left, Middle and Right.
    static func choices(onNotchedScreen notched: Bool) -> [StripAlignment] {
        notched ? [.center, .right] : [.left, .center, .right]
    }

    /// On a notched screen the strip's region is the left part of the bar. Left hugs the Apple menu side
    /// and Middle sits against the notch. Off a notch, Middle centers and Right hugs the trailing edge.
    func title(onNotchedScreen notched: Bool) -> String {
        switch self {
        case .left: return "Left"
        case .center: return notched ? "Left" : "Middle"
        case .right: return notched ? "Middle" : "Right"
        }
    }
}

/// Every setting that has its own reset control in Settings. Pinned apps are not here: they are a list the
/// user built, not a preference with a default, so "Reset all" leaves them alone (each has its own Unpin).
enum SettingID: CaseIterable {
    case order, label, shrinkWhenCrowded, maxTabs
    case theme, style, equalTabWidth, maxTabWidth, tabHeightPercent, indicator
    case useSystemAccent, customAccent, widthMode, stripWidth, alignment, coverAppleMenu
    case showOnAllDisplays, disabledDisplays
    case hideWhenSingleWindow, hideInFullScreen, includeMinimized, ignoreSmallWindows, smallWindowSize
    case hideDurations, showSettingsOnReopen
}

final class Settings: ObservableObject {
    /// Demo mode (`-mw.demo YES`) uses a throwaway store so it never touches the real settings.
    static let shared = Settings(store: DemoMode.isOn ? DemoMode.store : .standard)

    enum Defaults {
        static let order = TabOrderMode.automatic
        static let label = TabLabelMode.appAndTitle
        static let shrinkWhenCrowded = true
        static let style = TabStyle.square
        static let theme = ColorTheme.system
        static let equalTabWidth = true
        static let maxTabWidth: Double = 220
        static let tabHeightPercent: Double = 85
        static let indicator = ActiveIndicator.brighterFill
        static let useSystemAccent = true
        static let customAccent: [Double] = [0.95, 0.55, 0.15, 1]
        static let widthMode = StripWidthMode.automatic
        static let stripWidth: Double = 560
        static let alignment = StripAlignment.center
        static let coverAppleMenu = false
        static let maxTabs = 8
        static let showOnAllDisplays = true
        static let disabledDisplays: [String] = []
        static let hideWhenSingleWindow = false
        static let hideInFullScreen = true
        static let includeMinimized = false
        static let ignoreSmallWindows = true
        static let smallWindowSize: Double = 100
        static let hideDurations = [10, 30, 60]
        static let showSettingsOnReopen = true
    }

    static let maxTabWidthRange: ClosedRange<Double> = 120...400
    static let tabHeightRange: ClosedRange<Double> = 50...100
    static let stripWidthRange: ClosedRange<Double> = 240...900
    static let maxTabsRange: ClosedRange<Int> = 3...12
    static let smallWindowRange: ClosedRange<Double> = 40...300

    private let store: UserDefaults

    // Tabs and order
    @Published var order: TabOrderMode { didSet { store.set(order.rawValue, forKey: Key.order) } }
    /// App keys (bundle identifiers) in pin order.
    @Published var pinnedApps: [String] { didSet { store.set(pinnedApps, forKey: Key.pinnedApps) } }
    @Published var label: TabLabelMode { didSet { store.set(label.rawValue, forKey: Key.label) } }
    @Published var shrinkWhenCrowded: Bool { didSet { store.set(shrinkWhenCrowded, forKey: Key.shrink) } }
    @Published var maxTabs: Int { didSet { store.set(maxTabs, forKey: Key.maxTabs) } }

    // Appearance
    /// Tab height as a percentage of the menu bar height. Tabs stay flush with the top edge.
    @Published var tabHeightPercent: Double { didSet { store.set(tabHeightPercent, forKey: Key.tabHeight) } }
    /// Every tab gets the same width and the tabs share the available space, like browser tabs.
    @Published var equalTabWidth: Bool { didSet { store.set(equalTabWidth, forKey: Key.equalWidth) } }
    /// Widest a tab may grow when there is plenty of room (equal widths only).
    @Published var maxTabWidth: Double { didSet { store.set(maxTabWidth, forKey: Key.maxTabWidth) } }
    @Published var theme: ColorTheme { didSet { store.set(theme.rawValue, forKey: Key.theme) } }
    @Published var style: TabStyle { didSet { store.set(style.rawValue, forKey: Key.style) } }
    @Published var indicator: ActiveIndicator { didSet { store.set(indicator.rawValue, forKey: Key.indicator) } }
    @Published var useSystemAccent: Bool { didSet { store.set(useSystemAccent, forKey: Key.useSystemAccent) } }
    @Published var customAccent: [Double] { didSet { store.set(customAccent, forKey: Key.customAccent) } }
    @Published var widthMode: StripWidthMode { didSet { store.set(widthMode.rawValue, forKey: Key.widthMode) } }
    @Published var stripWidth: Double { didSet { store.set(stripWidth, forKey: Key.stripWidth) } }
    @Published var coverAppleMenu: Bool { didSet { store.set(coverAppleMenu, forKey: Key.coverAppleMenu) } }
    @Published var alignment: StripAlignment { didSet { store.set(alignment.rawValue, forKey: Key.alignment) } }

    // Displays
    @Published var showOnAllDisplays: Bool { didSet { store.set(showOnAllDisplays, forKey: Key.allDisplays) } }
    /// Display UUIDs the user turned off. Only used when showOnAllDisplays is off.
    @Published var disabledDisplays: [String] { didSet { store.set(disabledDisplays, forKey: Key.disabledDisplays) } }

    // Behaviour
    @Published var hideWhenSingleWindow: Bool { didSet { store.set(hideWhenSingleWindow, forKey: Key.hideSingle) } }
    @Published var hideInFullScreen: Bool { didSet { store.set(hideInFullScreen, forKey: Key.hideFullScreen) } }
    @Published var includeMinimized: Bool { didSet { store.set(includeMinimized, forKey: Key.includeMinimized) } }
    @Published var ignoreSmallWindows: Bool { didSet { store.set(ignoreSmallWindows, forKey: Key.ignoreSmall) } }
    @Published var smallWindowSize: Double { didSet { store.set(smallWindowSize, forKey: Key.smallSize) } }
    @Published var hideDurations: [Int] { didSet { store.set(hideDurations, forKey: Key.hideDurations) } }

    // General
    @Published var showSettingsOnReopen: Bool { didSet { store.set(showSettingsOnReopen, forKey: Key.reopen) } }
    @Published var hasCompletedOnboarding: Bool { didSet { store.set(hasCompletedOnboarding, forKey: Key.onboarded) } }

    private enum Key {
        static let order = "mw.order"
        static let pinnedApps = "mw.pinnedApps"
        static let label = "mw.label"
        static let shrink = "mw.shrinkWhenCrowded"
        static let maxTabs = "mw.maxTabs"
        static let style = "mw.style"
        static let theme = "mw.colorTheme"
        static let equalWidth = "mw.equalTabWidth"
        static let maxTabWidth = "mw.maxTabWidth"
        static let tabHeight = "mw.tabHeightPercent"
        static let indicator = "mw.indicator"
        static let useSystemAccent = "mw.useSystemAccent"
        static let customAccent = "mw.customAccent"
        static let widthMode = "mw.widthMode"
        static let stripWidth = "mw.stripWidth"
        static let alignment = "mw.alignment"
        static let coverAppleMenu = "mw.coverAppleMenu"
        static let allDisplays = "mw.showOnAllDisplays"
        static let disabledDisplays = "mw.disabledDisplays"
        static let hideSingle = "mw.hideWhenSingleWindow"
        static let hideFullScreen = "mw.hideInFullScreen"
        static let includeMinimized = "mw.includeMinimized"
        static let ignoreSmall = "mw.ignoreSmallWindows"
        static let smallSize = "mw.smallWindowSize"
        static let hideDurations = "mw.hideDurations"
        static let reopen = "mw.showSettingsOnReopen"
        static let onboarded = "mw.hasCompletedOnboarding"
    }

    init(store: UserDefaults = .standard) {
        self.store = store
        // Typed readers. Values given as launch arguments (for example `-mw.maxTabs 5`) arrive as
        // strings, so Bool, Int and Double go through UserDefaults' converting getters.
        func value(_ key: String, _ fallback: Bool) -> Bool {
            store.object(forKey: key) == nil ? fallback : store.bool(forKey: key)
        }
        func value(_ key: String, _ fallback: Int) -> Int {
            store.object(forKey: key) == nil ? fallback : store.integer(forKey: key)
        }
        func value(_ key: String, _ fallback: Double) -> Double {
            store.object(forKey: key) == nil ? fallback : store.double(forKey: key)
        }
        func value<T>(_ key: String, _ fallback: [T]) -> [T] { store.array(forKey: key) as? [T] ?? fallback }
        func choice<T: RawRepresentable>(_ key: String, _ fallback: T) -> T where T.RawValue == String {
            store.string(forKey: key).flatMap(T.init(rawValue:)) ?? fallback
        }

        order = choice(Key.order, Defaults.order)
        pinnedApps = value(Key.pinnedApps, [])
        label = choice(Key.label, Defaults.label)
        shrinkWhenCrowded = value(Key.shrink, Defaults.shrinkWhenCrowded)
        maxTabs = min(max(value(Key.maxTabs, Defaults.maxTabs), Self.maxTabsRange.lowerBound), Self.maxTabsRange.upperBound)
        style = choice(Key.style, Defaults.style)
        theme = choice(Key.theme, Defaults.theme)
        equalTabWidth = value(Key.equalWidth, Defaults.equalTabWidth)
        maxTabWidth = min(max(value(Key.maxTabWidth, Defaults.maxTabWidth), Self.maxTabWidthRange.lowerBound), Self.maxTabWidthRange.upperBound)
        tabHeightPercent = min(max(value(Key.tabHeight, Defaults.tabHeightPercent), Self.tabHeightRange.lowerBound), Self.tabHeightRange.upperBound)
        indicator = choice(Key.indicator, Defaults.indicator)
        useSystemAccent = value(Key.useSystemAccent, Defaults.useSystemAccent)
        let accent: [Double] = value(Key.customAccent, Defaults.customAccent)
        customAccent = accent.count == 4 ? accent : Defaults.customAccent
        widthMode = choice(Key.widthMode, Defaults.widthMode)
        stripWidth = min(max(value(Key.stripWidth, Defaults.stripWidth), Self.stripWidthRange.lowerBound), Self.stripWidthRange.upperBound)
        alignment = choice(Key.alignment, Defaults.alignment)
        coverAppleMenu = value(Key.coverAppleMenu, Defaults.coverAppleMenu)
        showOnAllDisplays = value(Key.allDisplays, Defaults.showOnAllDisplays)
        disabledDisplays = value(Key.disabledDisplays, Defaults.disabledDisplays)
        hideWhenSingleWindow = value(Key.hideSingle, Defaults.hideWhenSingleWindow)
        hideInFullScreen = value(Key.hideFullScreen, Defaults.hideInFullScreen)
        includeMinimized = value(Key.includeMinimized, Defaults.includeMinimized)
        ignoreSmallWindows = value(Key.ignoreSmall, Defaults.ignoreSmallWindows)
        smallWindowSize = value(Key.smallSize, Defaults.smallWindowSize)
        let durations: [Int] = value(Key.hideDurations, Defaults.hideDurations)
        hideDurations = durations.isEmpty ? Defaults.hideDurations : durations
        showSettingsOnReopen = value(Key.reopen, Defaults.showSettingsOnReopen)
        hasCompletedOnboarding = value(Key.onboarded, false)

        objectWillChangeSink = objectWillChange
            .debounce(for: .zero, scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.changesSubject.send(()) }
    }

    private let changesSubject = PassthroughSubject<Void, Never>()
    private var objectWillChangeSink: AnyCancellable?

    /// Fires on the main queue after any setting has changed (debounced to one event per loop turn).
    /// Subscribe here for live updates.
    var didChange: AnyPublisher<Void, Never> { changesSubject.eraseToAnyPublisher() }

    // MARK: Derived values

    var accentColor: NSColor {
        guard !useSystemAccent, customAccent.count == 4 else { return .controlAccentColor }
        return NSColor(
            srgbRed: customAccent[0], green: customAccent[1], blue: customAccent[2], alpha: customAccent[3]
        )
    }

    func setCustomAccent(_ color: NSColor) {
        guard let rgb = color.usingColorSpace(.sRGB) else { return }
        customAccent = [
            Double(rgb.redComponent), Double(rgb.greenComponent),
            Double(rgb.blueComponent), Double(rgb.alphaComponent)
        ]
    }

    func isPinned(_ appKey: String) -> Bool { pinnedApps.contains(appKey) }

    func togglePin(_ appKey: String) {
        if let index = pinnedApps.firstIndex(of: appKey) {
            pinnedApps.remove(at: index)
        } else {
            pinnedApps.append(appKey)
            // Pinning only has an effect in the pinned order mode, so switch to it.
            if order != .pinnedFirst { order = .pinnedFirst }
        }
    }

    func isDisplayEnabled(_ uuid: String) -> Bool {
        showOnAllDisplays || !disabledDisplays.contains(uuid)
    }

    func setDisplay(_ uuid: String, enabled: Bool) {
        var set = Set(disabledDisplays)
        if enabled { set.remove(uuid) } else { set.insert(uuid) }
        disabledDisplays = set.sorted()
    }

    /// Parses "10, 30, 60" into sorted, unique, positive seconds (max 3600). Returns nil when empty.
    static func parseDurations(_ text: String) -> [Int]? {
        let values = text
            .split(whereSeparator: { $0 == "," || $0 == " " })
            .compactMap { Int($0) }
            .filter { $0 > 0 && $0 <= 3600 }
        let unique = Array(Set(values)).sorted()
        return unique.isEmpty ? nil : Array(unique.prefix(6))
    }

    /// Whether a setting already has its default value. Its reset control is disabled when this is true.
    func isDefault(_ setting: SettingID) -> Bool {
        switch setting {
        case .order: return order == Defaults.order
        case .label: return label == Defaults.label
        case .shrinkWhenCrowded: return shrinkWhenCrowded == Defaults.shrinkWhenCrowded
        case .maxTabs: return maxTabs == Defaults.maxTabs
        case .theme: return theme == Defaults.theme
        case .style: return style == Defaults.style
        case .equalTabWidth: return equalTabWidth == Defaults.equalTabWidth
        case .maxTabWidth: return maxTabWidth == Defaults.maxTabWidth
        case .tabHeightPercent: return tabHeightPercent == Defaults.tabHeightPercent
        case .indicator: return indicator == Defaults.indicator
        case .useSystemAccent: return useSystemAccent == Defaults.useSystemAccent
        case .customAccent: return customAccent == Defaults.customAccent
        case .widthMode: return widthMode == Defaults.widthMode
        case .stripWidth: return stripWidth == Defaults.stripWidth
        case .alignment: return alignment == Defaults.alignment
        case .coverAppleMenu: return coverAppleMenu == Defaults.coverAppleMenu
        case .showOnAllDisplays: return showOnAllDisplays == Defaults.showOnAllDisplays
        case .disabledDisplays: return disabledDisplays == Defaults.disabledDisplays
        case .hideWhenSingleWindow: return hideWhenSingleWindow == Defaults.hideWhenSingleWindow
        case .hideInFullScreen: return hideInFullScreen == Defaults.hideInFullScreen
        case .includeMinimized: return includeMinimized == Defaults.includeMinimized
        case .ignoreSmallWindows: return ignoreSmallWindows == Defaults.ignoreSmallWindows
        case .smallWindowSize: return smallWindowSize == Defaults.smallWindowSize
        case .hideDurations: return hideDurations == Defaults.hideDurations
        case .showSettingsOnReopen: return showSettingsOnReopen == Defaults.showSettingsOnReopen
        }
    }

    /// Restores one setting to its default by assigning its published property, so the usual change path
    /// runs (save, then `didChange`). It only sets the order mode: the manual drag order is not touched.
    func reset(_ setting: SettingID) {
        switch setting {
        case .order: order = Defaults.order
        case .label: label = Defaults.label
        case .shrinkWhenCrowded: shrinkWhenCrowded = Defaults.shrinkWhenCrowded
        case .maxTabs: maxTabs = Defaults.maxTabs
        case .theme: theme = Defaults.theme
        case .style: style = Defaults.style
        case .equalTabWidth: equalTabWidth = Defaults.equalTabWidth
        case .maxTabWidth: maxTabWidth = Defaults.maxTabWidth
        case .tabHeightPercent: tabHeightPercent = Defaults.tabHeightPercent
        case .indicator: indicator = Defaults.indicator
        case .useSystemAccent: useSystemAccent = Defaults.useSystemAccent
        case .customAccent: customAccent = Defaults.customAccent
        case .widthMode: widthMode = Defaults.widthMode
        case .stripWidth: stripWidth = Defaults.stripWidth
        case .alignment: alignment = Defaults.alignment
        case .coverAppleMenu: coverAppleMenu = Defaults.coverAppleMenu
        case .showOnAllDisplays: showOnAllDisplays = Defaults.showOnAllDisplays
        case .disabledDisplays: disabledDisplays = Defaults.disabledDisplays
        case .hideWhenSingleWindow: hideWhenSingleWindow = Defaults.hideWhenSingleWindow
        case .hideInFullScreen: hideInFullScreen = Defaults.hideInFullScreen
        case .includeMinimized: includeMinimized = Defaults.includeMinimized
        case .ignoreSmallWindows: ignoreSmallWindows = Defaults.ignoreSmallWindows
        case .smallWindowSize: smallWindowSize = Defaults.smallWindowSize
        case .hideDurations: hideDurations = Defaults.hideDurations
        case .showSettingsOnReopen: showSettingsOnReopen = Defaults.showSettingsOnReopen
        }
    }

    /// Restores every `SettingID` to its default. Pinned apps, onboarding and launch at login are not
    /// settings in this sense, so they are left alone.
    func resetToDefaults() {
        for setting in SettingID.allCases { reset(setting) }
    }
}

/// Connected displays with a stable identifier and a human name.
enum Displays {
    static func uuid(of screen: NSScreen) -> String {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let uuid = CGDisplayCreateUUIDFromDisplayID(CGDirectDisplayID(number.uint32Value))?
                .takeRetainedValue(),
              let text = CFUUIDCreateString(nil, uuid) as String? else {
            return NSStringFromRect(screen.frame)
        }
        return text
    }

    static func name(of screen: NSScreen) -> String {
        screen.localizedName
    }
}
