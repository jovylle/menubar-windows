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
    case center
    case left
    var id: String { rawValue }
    var title: String {
        switch self {
        case .center: return "Center"
        case .left: return "Left"
        }
    }
}

final class Settings: ObservableObject {
    static let shared = Settings()

    enum Defaults {
        static let order = TabOrderMode.automatic
        static let label = TabLabelMode.appAndTitle
        static let shrinkWhenCrowded = true
        static let style = TabStyle.square
        static let theme = ColorTheme.system
        static let indicator = ActiveIndicator.both
        static let useSystemAccent = true
        static let customAccent: [Double] = [0.95, 0.55, 0.15, 1]
        static let widthMode = StripWidthMode.automatic
        static let stripWidth: Double = 560
        static let alignment = StripAlignment.center
        static let maxTabs = 8
        static let showOnAllDisplays = true
        static let hideWhenSingleWindow = false
        static let hideInFullScreen = true
        static let includeMinimized = false
        static let ignoreSmallWindows = true
        static let smallWindowSize: Double = 100
        static let hideDurations = [10, 30, 60]
        static let showSettingsOnReopen = true
    }

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
    @Published var theme: ColorTheme { didSet { store.set(theme.rawValue, forKey: Key.theme) } }
    @Published var style: TabStyle { didSet { store.set(style.rawValue, forKey: Key.style) } }
    @Published var indicator: ActiveIndicator { didSet { store.set(indicator.rawValue, forKey: Key.indicator) } }
    @Published var useSystemAccent: Bool { didSet { store.set(useSystemAccent, forKey: Key.useSystemAccent) } }
    @Published var customAccent: [Double] { didSet { store.set(customAccent, forKey: Key.customAccent) } }
    @Published var widthMode: StripWidthMode { didSet { store.set(widthMode.rawValue, forKey: Key.widthMode) } }
    @Published var stripWidth: Double { didSet { store.set(stripWidth, forKey: Key.stripWidth) } }
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
        static let indicator = "mw.indicator"
        static let useSystemAccent = "mw.useSystemAccent"
        static let customAccent = "mw.customAccent"
        static let widthMode = "mw.widthMode"
        static let stripWidth = "mw.stripWidth"
        static let alignment = "mw.alignment"
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
        indicator = choice(Key.indicator, Defaults.indicator)
        useSystemAccent = value(Key.useSystemAccent, Defaults.useSystemAccent)
        let accent: [Double] = value(Key.customAccent, Defaults.customAccent)
        customAccent = accent.count == 4 ? accent : Defaults.customAccent
        widthMode = choice(Key.widthMode, Defaults.widthMode)
        stripWidth = min(max(value(Key.stripWidth, Defaults.stripWidth), Self.stripWidthRange.lowerBound), Self.stripWidthRange.upperBound)
        alignment = choice(Key.alignment, Defaults.alignment)
        showOnAllDisplays = value(Key.allDisplays, Defaults.showOnAllDisplays)
        disabledDisplays = value(Key.disabledDisplays, [])
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

    /// Restores every setting to its default. Pins and onboarding state are kept unless asked.
    func resetToDefaults(includingPins: Bool = true) {
        order = Defaults.order
        if includingPins { pinnedApps = [] }
        label = Defaults.label
        shrinkWhenCrowded = Defaults.shrinkWhenCrowded
        maxTabs = Defaults.maxTabs
        style = Defaults.style
        indicator = Defaults.indicator
        useSystemAccent = Defaults.useSystemAccent
        customAccent = Defaults.customAccent
        widthMode = Defaults.widthMode
        stripWidth = Defaults.stripWidth
        alignment = Defaults.alignment
        showOnAllDisplays = Defaults.showOnAllDisplays
        disabledDisplays = []
        hideWhenSingleWindow = Defaults.hideWhenSingleWindow
        hideInFullScreen = Defaults.hideInFullScreen
        includeMinimized = Defaults.includeMinimized
        ignoreSmallWindows = Defaults.ignoreSmallWindows
        smallWindowSize = Defaults.smallWindowSize
        hideDurations = Defaults.hideDurations
        showSettingsOnReopen = Defaults.showSettingsOnReopen
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
