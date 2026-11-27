// SettingsView.swift
// The Settings window: Appearance, Tabs and order, Displays, Behaviour, General, About.
// Every control binds straight to Settings.shared, which persists and broadcasts the change, so the
// strip updates while the window is open. Deployment target is macOS 13, so only macOS 13 SwiftUI
// API is used (Form with .grouped style, TabView, ColorPicker with a CGColor binding).
//
// Gotchas:
// - Help text sits under each control as secondary callout text; meaning is never color-only.
// - The display list re-reads NSScreen.screens when screens change, so a newly plugged display shows.
// - Hide durations are typed as text ("10, 30, 60") and only saved when they parse.
// - `-mw.settingsPane <name>` picks the first pane (SettingsPane raw values). Demo mode shows invented
//   displays and pinned app names (DemoMode), never the real ones.
// - Each setting control is wrapped in `Resettable`: a reset arrow that calls Settings.reset and is
//   disabled at the default. The defaults come only from Settings.swift, never from this file. Pinned
//   apps have no reset arrow (they have Unpin) and launch at login is system state, not a setting.
// - "Reset all to defaults" lives on About and asks first (confirmation dialog). It keeps pinned apps.

import AppKit
import MenubarWindowsCore
import SwiftUI

enum SettingsPane: String, CaseIterable {
    case appearance
    case tabs
    case displays
    case behaviour
    case general
    case about

    /// The pane named by `-mw.settingsPane`, else Appearance. "order" and "behavior" are accepted too.
    static var initial: SettingsPane {
        switch UserDefaults.standard.string(forKey: "mw.settingsPane")?.lowercased() {
        case "order": return .tabs
        case "behavior": return .behaviour
        case let name?: return SettingsPane(rawValue: name) ?? .appearance
        case nil: return .appearance
        }
    }
}

struct SettingsView: View {
    @ObservedObject var settings: Settings
    @State private var pane = SettingsPane.initial

    var body: some View {
        TabView(selection: $pane) {
            AppearancePane(settings: settings)
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
                .tag(SettingsPane.appearance)
            TabsPane(settings: settings)
                .tabItem { Label("Tabs and order", systemImage: "rectangle.split.3x1") }
                .tag(SettingsPane.tabs)
            DisplaysPane(settings: settings)
                .tabItem { Label("Displays", systemImage: "display.2") }
                .tag(SettingsPane.displays)
            BehaviourPane(settings: settings)
                .tabItem { Label("Behaviour", systemImage: "slider.horizontal.3") }
                .tag(SettingsPane.behaviour)
            GeneralPane(settings: settings)
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsPane.general)
            AboutPane(settings: settings)
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag(SettingsPane.about)
        }
        .padding(.top, 8)
        .frame(width: 620, height: 600)
    }
}

// MARK: Shared pieces

private struct Help: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A setting's control with a small reset arrow after it. The arrow is disabled while the setting is at its
/// default, and pressing it restores only that setting.
private struct Resettable<Content: View>: View {
    @ObservedObject var settings: Settings
    let setting: SettingID
    let content: Content

    init(_ settings: Settings, _ setting: SettingID, @ViewBuilder content: () -> Content) {
        self._settings = ObservedObject(wrappedValue: settings)
        self.setting = setting
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 8) {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                settings.reset(setting)
            } label: {
                Image(systemName: "arrow.counterclockwise")
            }
            .buttonStyle(.borderless)
            .disabled(settings.isDefault(setting))
            .help("Reset to the default")
            .accessibilityLabel("Reset to the default")
        }
    }
}

private struct PreviewSection: View {
    @ObservedObject var settings: Settings
    var body: some View {
        Section {
            StripPreview(settings: settings)
                .frame(height: 46)
                .accessibilityLabel("Live preview of the tab strip")
            Help("Order: \(settings.order.title). Labels: \(settings.label.title). "
                + "Style: \(settings.style.title), active tab shown with \(settings.indicator.title.lowercased()).")
        } header: {
            Text("Preview")
        }
    }
}

// MARK: Appearance

private struct AppearancePane: View {
    @ObservedObject var settings: Settings

    private var onNotchedScreen: Bool {
        NSScreen.screens.contains { $0.auxiliaryTopLeftArea != nil }
    }

    private var accentBinding: Binding<CGColor> {
        Binding(
            get: { settings.accentColor.cgColor },
            set: { cgColor in
                if let color = NSColor(cgColor: cgColor) { settings.setCustomAccent(color) }
            }
        )
    }

    var body: some View {
        Form {
            PreviewSection(settings: settings)

            Section("Tabs") {
                Resettable(settings, .theme) {
                    Picker("Color theme", selection: $settings.theme) {
                        ForEach(ColorTheme.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.radioGroup)
                }
                Help("Pure black keeps every tab black with white text, whatever the system appearance. "
                    + "The active tab has full-white text and the others are slightly dimmer.")

                Resettable(settings, .equalTabWidth) {
                    Toggle("Same width for every tab", isOn: $settings.equalTabWidth)
                }
                Resettable(settings, .maxTabWidth) {
                    HStack {
                        Slider(value: $settings.maxTabWidth, in: Settings.maxTabWidthRange, step: 10) {
                            Text("Widest tab")
                        }
                        Text("\(Int(settings.maxTabWidth)) pt")
                            .monospacedDigit()
                            .frame(width: 70, alignment: .trailing)
                    }
                    .disabled(!settings.equalTabWidth)
                }
                Help("Tabs share the room in the bar equally, like browser tabs, and shrink as more windows open. "
                    + "Very narrow tabs show only the app icon.")

                Resettable(settings, .style) {
                    Picker("Tab style", selection: $settings.style) {
                        ForEach(TabStyle.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.radioGroup)
                }
                Help("Square tabs touch the top edge of the screen and flare out into it, like an upside-down "
                    + "browser tab. Rounded tabs are inset, with four rounded corners.")

                Resettable(settings, .indicator) {
                    Picker("Active tab", selection: $settings.indicator) {
                        ForEach(ActiveIndicator.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                Help("How the focused window's tab stands out. Underline uses the accent color. Pure black "
                    + "has no brighter fill; its active tab has full-white text instead.")

                Resettable(settings, .useSystemAccent) {
                    Toggle("Use the system accent color", isOn: $settings.useSystemAccent)
                }
                Resettable(settings, .customAccent) {
                    ColorPicker("Custom accent color", selection: accentBinding, supportsOpacity: false)
                        .disabled(settings.useSystemAccent)
                }
                Help("Set in System Settings, Appearance, unless you pick a custom color here.")
            }

            Section("Strip") {
                Resettable(settings, .tabHeightPercent) {
                    HStack {
                        Slider(value: $settings.tabHeightPercent, in: Settings.tabHeightRange, step: 5) {
                            Text("Tab height")
                        }
                        Text("\(Int(settings.tabHeightPercent))% of the menu bar")
                            .monospacedDigit()
                            .frame(width: 150, alignment: .trailing)
                    }
                }
                Help("Tabs stay flush with the top. A shorter tab leaves the bottom of the menu bar clear.")

                Resettable(settings, .widthMode) {
                    Picker("Width", selection: $settings.widthMode) {
                        ForEach(StripWidthMode.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.radioGroup)
                }
                Resettable(settings, .stripWidth) {
                    HStack {
                        Slider(value: $settings.stripWidth, in: Settings.stripWidthRange, step: 10) {
                            Text(settings.widthMode == .automatic ? "Maximum width" : "Width")
                        }
                        Text("\(Int(settings.stripWidth)) pt")
                            .monospacedDigit()
                            .frame(width: 60, alignment: .trailing)
                    }
                }
                Help(settings.widthMode == .automatic
                    ? "The strip grows with your tabs up to this width, and leaves the rest of the menu bar clickable. "
                        + "On a screen with a notch it may use all the space between the Apple menu and the notch."
                    : "The strip always takes this width. Empty space in it does not pass clicks to the menu bar.")

                Resettable(settings, .alignment) {
                    Picker("Alignment", selection: $settings.alignment) {
                        ForEach(StripAlignment.allCases) { Text($0.title(onNotchedScreen: onNotchedScreen)).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                Help(onNotchedScreen
                    ? "With three or more tabs the strip fills the whole space. With fewer, Left starts them right after "
                        + "the Apple menu, and Middle puts them next to the notch."
                    : "With three or more tabs the strip fills the whole space. With fewer, Middle centers them and "
                        + "Right puts them at the end.")

                Resettable(settings, .coverAppleMenu) {
                    Toggle("Cover the Apple menu (screens with a notch)", isOn: $settings.coverAppleMenu)
                }
                Help("With Left on a screen with a notch, the first tab starts at the very left edge, so pushing the pointer "
                    + "into the top left corner selects it. The Apple menu is then hidden underneath; right-click a tab and "
                    + "choose Hide for to reach it.")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: Tabs and order

private struct TabsPane: View {
    @ObservedObject var settings: Settings

    var body: some View {
        Form {
            PreviewSection(settings: settings)

            Section("Order") {
                Resettable(settings, .order) {
                    Picker("Tab order", selection: $settings.order) {
                        ForEach(TabOrderMode.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.radioGroup)
                }
                Help(settings.order.help)
            }

            Section("Pinned apps") {
                if settings.pinnedApps.isEmpty {
                    Help("No pinned apps. Right-click a tab and choose Pin to put its app first.")
                } else {
                    ForEach(settings.pinnedApps, id: \.self) { key in
                        HStack {
                            Text(Self.appName(for: key))
                            Spacer()
                            Button("Unpin") { settings.togglePin(key) }
                                .accessibilityLabel("Unpin \(Self.appName(for: key))")
                        }
                    }
                    Help("Pinned apps come first, in this order, when the order is \(TabOrderMode.pinnedFirst.title).")
                }
            }

            Section("Labels") {
                Resettable(settings, .label) {
                    Picker("Show", selection: $settings.label) {
                        ForEach(TabLabelMode.allCases) { Text($0.title).tag($0) }
                    }
                }
                Resettable(settings, .shrinkWhenCrowded) {
                    Toggle("Shrink to icon-only when crowded", isOn: $settings.shrinkWhenCrowded)
                }
                Help("When the tabs do not fit, they drop their labels before they shrink or scroll.")

                Resettable(settings, .maxTabs) {
                    Stepper(value: $settings.maxTabs, in: Settings.maxTabsRange) {
                        Text("Show up to \(settings.maxTabs) tabs")
                    }
                }
                Help("Extra windows go into a +N tab at the end. Click it for a menu of the rest.")
            }
        }
        .formStyle(.grouped)
    }

    static func appName(for key: String) -> String {
        if DemoMode.isOn { return DemoMode.appName(forKey: key) }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: key) {
            return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        }
        return key
    }
}

// MARK: Displays

private struct DisplaysPane: View {
    @ObservedObject var settings: Settings
    @State private var screens: [ScreenRow] = ScreenRow.current()

    struct ScreenRow: Identifiable {
        let id: String
        let name: String
        let detail: String

        static func current() -> [ScreenRow] {
            if DemoMode.isOn {
                return [
                    ScreenRow(id: "demo-built-in", name: DemoData.displayNames[0],
                              detail: "1512 x 982 pt, main display, has a notch"),
                    ScreenRow(id: "demo-external", name: DemoData.displayNames[1], detail: "2560 x 1440 pt")
                ]
            }
            return NSScreen.screens.enumerated().map { index, screen in
                let size = "\(Int(screen.frame.width)) x \(Int(screen.frame.height)) pt"
                var notes = [size]
                if index == 0 { notes.append("main display") }
                if screen.auxiliaryTopLeftArea != nil { notes.append("has a notch") }
                return ScreenRow(id: Displays.uuid(of: screen), name: Displays.name(of: screen),
                                 detail: notes.joined(separator: ", "))
            }
        }
    }

    var body: some View {
        Form {
            Section {
                Resettable(settings, .showOnAllDisplays) {
                    Toggle("Show on all displays", isOn: $settings.showOnAllDisplays)
                }
                Help("Turn this off to choose displays one by one.")
            }
            Section {
                ForEach(screens) { row in
                    Toggle(isOn: Binding(
                        get: { settings.isDisplayEnabled(row.id) },
                        set: { settings.setDisplay(row.id, enabled: $0) }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.name)
                            Help(row.detail)
                        }
                    }
                    .disabled(settings.showOnAllDisplays)
                }
                Help("A display only shows tabs while it has a visible menu bar.")
            } header: {
                // The reset arrow for the whole list of per-display choices.
                Resettable(settings, .disabledDisplays) {
                    Text("Connected displays")
                }
            }
        }
        .formStyle(.grouped)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            screens = ScreenRow.current()
        }
    }
}

// MARK: Behaviour

private struct BehaviourPane: View {
    @ObservedObject var settings: Settings
    @State private var durationsText = ""
    @State private var durationsError = false

    var body: some View {
        Form {
            Section("When to hide") {
                Resettable(settings, .hideWhenSingleWindow) {
                    Toggle("Hide when only one window is open", isOn: $settings.hideWhenSingleWindow)
                }
                Help("Counted per display.")
                Resettable(settings, .hideInFullScreen) {
                    Toggle("Hide in full-screen apps", isOn: $settings.hideInFullScreen)
                }
                Help("The menu bar is hidden in full screen, so the strip steps aside too.")
            }

            Section("Which windows get a tab") {
                Resettable(settings, .includeMinimized) {
                    Toggle("Include minimized windows", isOn: $settings.includeMinimized)
                }
                Help("Minimized windows show as tabs with a dimmed icon; clicking one restores it. "
                    + "Off: they never appear.")

                Resettable(settings, .ignoreSmallWindows) {
                    Toggle("Ignore small helper windows", isOn: $settings.ignoreSmallWindows)
                }
                Resettable(settings, .smallWindowSize) {
                    HStack {
                        Slider(value: $settings.smallWindowSize, in: Settings.smallWindowRange, step: 10) {
                            Text("Smaller than")
                        }
                        Text("\(Int(settings.smallWindowSize)) pt")
                            .monospacedDigit()
                            .frame(width: 60, alignment: .trailing)
                    }
                    .disabled(!settings.ignoreSmallWindows)
                }
                Help("Skips find bars, popovers and palettes: windows the app marks as non-standard, "
                    + "or with a side shorter than this.")
            }

            Section("Hide on demand") {
                Resettable(settings, .hideDurations) {
                    TextField("Hide for (seconds)", text: $durationsText)
                        .onSubmit(saveDurations)
                        .onAppear { durationsText = Self.format(settings.hideDurations) }
                        .onChange(of: durationsText) { _ in durationsError = false }
                }
                HStack {
                    Help(durationsError
                        ? "Could not read that. Use whole seconds separated by commas, for example 10, 30, 60."
                        : "Right-click a tab and choose Hide for to reach the menus under the strip. "
                            + "Separate values with commas, then press Return.")
                    Spacer()
                    Button("Save", action: saveDurations)
                }
            }
        }
        .formStyle(.grouped)
        // A reset (or a save) changes the stored values; keep the text field showing them.
        .onChange(of: settings.hideDurations) { durations in
            durationsText = Self.format(durations)
            durationsError = false
        }
    }

    private func saveDurations() {
        if let values = Settings.parseDurations(durationsText) {
            settings.hideDurations = values
            durationsText = Self.format(values)
        } else {
            durationsError = true
        }
    }

    static func format(_ values: [Int]) -> String {
        values.map(String.init).joined(separator: ", ")
    }
}

// MARK: General

private struct GeneralPane: View {
    @ObservedObject var settings: Settings
    @StateObject private var loginItem = LoginItemModel()
    @StateObject private var permission = PermissionMonitor()

    var body: some View {
        Form {
            Section("Startup") {
                // Launch at login is system state (SMAppService), not a Settings value, so it has no reset arrow.
                Toggle("Launch at login", isOn: Binding(
                    get: { loginItem.isOn },
                    set: { loginItem.set($0) }
                ))
                .disabled(!loginItem.isAvailable)
                Help(loginItem.statusText)
                if let error = loginItem.lastError {
                    Help("Could not change it: \(error)")
                }
                if loginItem.status == .requiresApproval {
                    Button("Open Login Items Settings") { loginItem.openLoginItemsSettings() }
                }

                Resettable(settings, .showSettingsOnReopen) {
                    Toggle("Show Settings when the app is opened again", isOn: $settings.showSettingsOnReopen)
                }
                Help("There is no Dock icon or menu bar icon. Open the app again from Finder or Spotlight "
                    + "to get here, or right-click any tab and choose Settings.")
            }

            Section("Permission") {
                HStack {
                    Image(systemName: permission.isTrusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(permission.isTrusted ? .green : .orange)
                        .accessibilityHidden(true)
                    Text(permission.isTrusted ? "Accessibility access: granted" : "Accessibility access: not granted")
                    Spacer()
                    Button("Open setup guide") { OnboardingWindowController.shared.show() }
                }
                Help("Used to read window titles and to switch windows. Nothing leaves your Mac.")
            }
        }
        .formStyle(.grouped)
        .onAppear { loginItem.refresh() }
    }
}

// MARK: About

private struct AboutPane: View {
    @ObservedObject var settings: Settings
    @State private var confirmReset = false

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)
            Text(AppInfo.displayName)
                .font(.title)
                .bold()
            Text(AppInfo.tagline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text("Version \(AppInfo.version)")
                .monospacedDigit()
            Text("Free and open source (MIT). No network access and no analytics: nothing leaves your Mac.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text(AppInfo.copyright)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer().frame(height: 8)
            Button("Reset all to defaults…") { confirmReset = true }
                .confirmationDialog(
                    "Reset all settings to their defaults?",
                    isPresented: $confirmReset
                ) {
                    Button("Reset", role: .destructive) { settings.resetToDefaults() }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Your pinned apps are kept. Launch at login is not changed.")
                }
            Spacer()
        }
        .padding(32)
        .frame(maxWidth: .infinity)
    }
}
