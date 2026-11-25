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

import AppKit
import MenubarWindowsCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: Settings

    var body: some View {
        TabView {
            AppearancePane(settings: settings)
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
            TabsPane(settings: settings)
                .tabItem { Label("Tabs and order", systemImage: "rectangle.split.3x1") }
            DisplaysPane(settings: settings)
                .tabItem { Label("Displays", systemImage: "display.2") }
            BehaviourPane(settings: settings)
                .tabItem { Label("Behaviour", systemImage: "slider.horizontal.3") }
            GeneralPane(settings: settings)
                .tabItem { Label("General", systemImage: "gearshape") }
            AboutPane(settings: settings)
                .tabItem { Label("About", systemImage: "info.circle") }
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
                Picker("Color theme", selection: $settings.theme) {
                    ForEach(ColorTheme.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.radioGroup)
                Help("Pure black keeps every tab black with white text, whatever the system appearance. "
                    + "The active tab then has bold text and an accent underline.")

                Picker("Tab style", selection: $settings.style) {
                    ForEach(TabStyle.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.radioGroup)
                Help("Square tabs fill the full bar height and touch the top edge of the screen.")

                Picker("Active tab", selection: $settings.indicator) {
                    ForEach(ActiveIndicator.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Help("How the focused window's tab stands out. Underline uses the accent color.")

                Toggle("Use the system accent color", isOn: $settings.useSystemAccent)
                ColorPicker("Custom accent color", selection: accentBinding, supportsOpacity: false)
                    .disabled(settings.useSystemAccent)
                Help("Set in System Settings, Appearance, unless you pick a custom color here.")
            }

            Section("Strip") {
                HStack {
                    Slider(value: $settings.tabHeightPercent, in: Settings.tabHeightRange, step: 5) {
                        Text("Tab height")
                    }
                    Text("\(Int(settings.tabHeightPercent))% of the menu bar")
                        .monospacedDigit()
                        .frame(width: 150, alignment: .trailing)
                }
                Help("Tabs stay flush with the top. A shorter tab leaves the bottom of the menu bar clear.")

                Picker("Width", selection: $settings.widthMode) {
                    ForEach(StripWidthMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.radioGroup)
                HStack {
                    Slider(value: $settings.stripWidth, in: Settings.stripWidthRange, step: 10) {
                        Text(settings.widthMode == .automatic ? "Maximum width" : "Width")
                    }
                    Text("\(Int(settings.stripWidth)) pt")
                        .monospacedDigit()
                        .frame(width: 60, alignment: .trailing)
                }
                Help(settings.widthMode == .automatic
                    ? "The strip grows with your tabs up to this width, and leaves the rest of the menu bar clickable."
                    : "The strip always takes this width. Empty space in it does not pass clicks to the menu bar.")

                Picker("Alignment", selection: $settings.alignment) {
                    ForEach(StripAlignment.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Help("Center keeps the tabs in the middle of the bar, or next to the notch on screens that have one.")
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
                Picker("Tab order", selection: $settings.order) {
                    ForEach(TabOrderMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.radioGroup)
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
                Picker("Show", selection: $settings.label) {
                    ForEach(TabLabelMode.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Shrink to icon-only when crowded", isOn: $settings.shrinkWhenCrowded)
                Help("When the tabs do not fit, they drop their labels before they shrink or scroll.")

                Stepper(value: $settings.maxTabs, in: Settings.maxTabsRange) {
                    Text("Show up to \(settings.maxTabs) tabs")
                }
                Help("Extra windows go into a +N tab at the end. Click it for a menu of the rest.")
            }
        }
        .formStyle(.grouped)
    }

    static func appName(for key: String) -> String {
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
            NSScreen.screens.enumerated().map { index, screen in
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
                Toggle("Show on all displays", isOn: $settings.showOnAllDisplays)
                Help("Turn this off to choose displays one by one.")
            }
            Section("Connected displays") {
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
                Toggle("Hide when only one window is open", isOn: $settings.hideWhenSingleWindow)
                Help("Counted per display.")
                Toggle("Hide in full-screen apps", isOn: $settings.hideInFullScreen)
                Help("The menu bar is hidden in full screen, so the strip steps aside too.")
            }

            Section("Which windows get a tab") {
                Toggle("Include minimized windows", isOn: $settings.includeMinimized)
                Help("Minimized windows show as dimmed tabs; clicking one restores it. Off: they never appear.")

                Toggle("Ignore small helper windows", isOn: $settings.ignoreSmallWindows)
                HStack {
                    Slider(value: $settings.smallWindowSize, in: Settings.smallWindowRange, step: 10) {
                        Text("Smaller than")
                    }
                    Text("\(Int(settings.smallWindowSize)) pt")
                        .monospacedDigit()
                        .frame(width: 60, alignment: .trailing)
                }
                .disabled(!settings.ignoreSmallWindows)
                Help("Skips find bars, popovers and palettes: windows the app marks as non-standard, "
                    + "or with a side shorter than this.")
            }

            Section("Hide on demand") {
                TextField("Hide for (seconds)", text: $durationsText)
                    .onSubmit(saveDurations)
                    .onAppear { durationsText = Self.format(settings.hideDurations) }
                    .onChange(of: durationsText) { _ in durationsError = false }
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

                Toggle("Show Settings when the app is opened again", isOn: $settings.showSettingsOnReopen)
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
            Text("Private beta. No network access and no analytics: nothing leaves your Mac.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text(AppInfo.copyright)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer().frame(height: 8)
            Button("Reset to defaults…") { confirmReset = true }
                .confirmationDialog(
                    "Reset all settings to their defaults?",
                    isPresented: $confirmReset
                ) {
                    Button("Reset", role: .destructive) { settings.resetToDefaults() }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Pinned apps are cleared too. Launch at login is not changed.")
                }
            Spacer()
        }
        .padding(32)
        .frame(maxWidth: .infinity)
    }
}
