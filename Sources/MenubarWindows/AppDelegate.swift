// AppDelegate.swift
// Owns one StripPanel per screen, the tab order tracker, and two timers:
//   0.5s  refresh: strip region, show/hide, and tab contents for each screen
//   2.0s  Accessibility permission poll
// Panels are rebuilt on NSApplication.didChangeScreenParametersNotification. Everything is refreshed
// when another app activates and whenever a setting changes (Settings.didChange), so settings apply live.
//
// Gotchas:
// - Without Accessibility permission the window list is empty. The onboarding window explains why and
//   links to System Settings. Screen 0 also shows one "Grant Accessibility access" pill as a fallback
//   in case that window was closed; clicking it reopens onboarding.
// - The system Accessibility prompt is NOT shown at launch (onboarding replaces it). Onboarding's
//   button calls AXIsProcessTrustedWithOptions with the prompt once, which also adds the app to the
//   list in System Settings, then opens the pane.
// - There is no Dock icon and no status item by design, so opening the app again (double-click in
//   Finder, Spotlight) goes through applicationShouldHandleReopen, which opens Settings.
// - The order tracker is fed every refresh (first-seen order, focus changes) and by NSWorkspace
//   activation. It forgets a window only when CGWindowList no longer lists it at all, so a window on
//   another Space keeps its slot.
// - In Automatic width the panel is trimmed to the tabs, so the update must run before the frame is set.

import AppKit
import Combine
import MenubarWindowsCore

final class AppDelegate: NSObject, NSApplicationDelegate, StripActions {
    private struct ScreenStrip {
        let screen: NSScreen
        let displayID: String
        let panel: StripPanel
    }

    private let settings = Settings.shared
    private let tracker = WindowOrderTracker()
    private var strips: [ScreenStrip] = []
    private var trusted = false
    private var timers: [Timer] = []
    private var cancellables: Set<AnyCancellable> = []
    /// While set to a future date, every strip stays hidden so the menu titles underneath can be used.
    private var hiddenUntil: Date?
    private var lastFocusedID: CGWindowID?
    private var refreshCount = 0
    private var iconCache: [pid_t: NSImage] = [:]

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.make()
        trusted = AXIsProcessTrusted()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged(_:)),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appActivated(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        settings.didChange
            .sink { [weak self] in self?.settingsChanged() }
            .store(in: &cancellables)

        timers = [
            Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                self?.refresh()
            },
            Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
                self?.checkPermission()
            }
        ]

        rebuildPanels()
        if !trusted || !settings.hasCompletedOnboarding {
            OnboardingWindowController.shared.show()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !AXIsProcessTrusted() {
            OnboardingWindowController.shared.show()
        } else if settings.showSettingsOnReopen {
            openSettings()
        }
        return false
    }

    @objc private func screensChanged(_ notification: Notification) {
        rebuildPanels()
    }

    @objc private func appActivated(_ notification: Notification) {
        if trusted,
           let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
           let focused = WindowProvider.focusedWindowID(pid: app.processIdentifier) {
            noteFocus(focused)
        }
        refresh()
        // The new app's menu titles reach Accessibility a moment after activation, so measure again.
        for delay in [0.15, 0.4, 0.9] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.refresh()
            }
        }
    }

    private func settingsChanged() {
        strips.forEach { $0.panel.content.invalidate() }
        refresh()
    }

    private func rebuildPanels() {
        strips.forEach { $0.panel.orderOut(nil) }
        strips = NSScreen.screens.map {
            ScreenStrip(screen: $0, displayID: Displays.uuid(of: $0), panel: StripPanel())
        }
        for strip in strips {
            strip.panel.content.actions = self
        }
        refresh()
    }

    private func noteFocus(_ windowID: CGWindowID) {
        guard windowID != lastFocusedID else { return }
        lastFocusedID = windowID
        tracker.noteFocused(windowID)
    }

    // MARK: Refresh

    private func refresh() {
        if let until = hiddenUntil {
            if Date() < until {
                strips.forEach { $0.panel.orderOut(nil) }
                return
            }
            hiddenUntil = nil
        }

        let windows = trusted ? WindowProvider.allWindows() : []
        if let focused = windows.first(where: \.isFocused) {
            noteFocus(focused.windowID)
        }
        tracker.observe(windows.map(\.snapshot))
        refreshCount += 1
        if refreshCount % 20 == 0 {
            tracker.prune(keeping: WindowProvider.aliveWindowIDs())
            if iconCache.count > 200 { iconCache.removeAll() }
        }

        for (index, strip) in strips.enumerated() {
            guard settings.isDisplayEnabled(strip.displayID),
                  let region = MenuBarGeometry.freeStrip(
                      on: strip.screen,
                      width: CGFloat(settings.stripWidth),
                      alignment: settings.alignment,
                      placement: settings.placement,
                      hideInFullScreen: settings.hideInFullScreen
                  ) else {
                strip.panel.orderOut(nil)
                continue
            }

            var models: [PillModel] = []
            var overflow: [PillModel] = []
            if !trusted {
                if index == 0 { models = [permissionPill] }
            } else {
                let onScreen = orderedWindows(WindowProvider.windows(on: strip.screen, in: windows))
                if !(settings.hideWhenSingleWindow && onScreen.count <= 1) {
                    let all = onScreen.map(pillModel(for:))
                    let limit = settings.maxTabs
                    models = Array(all.prefix(limit))
                    overflow = Array(all.dropFirst(limit))
                }
            }

            guard !models.isEmpty else {
                strip.panel.orderOut(nil)
                continue
            }
            strip.panel.content.update(models, overflow: overflow)
            let width = strip.panel.content.preferredWidth(maximum: region.frame.width)
            var frame = region.panelFrame(contentWidth: width, mode: settings.widthMode)
            // Cover the menu titles: widen the panel to the left (to just after the Apple menu) and to the
            // right (to the end of the titles), and fill both sides of the tabs with a bar-colored filler.
            var tabsRange: StripContentView.TabsRange?
            if settings.coverMenuTitles, let menusMaxX = region.menusMaxX, menusMaxX > region.coverLeft {
                let left = min(frame.minX, region.coverLeft)
                let right = max(frame.maxX, min(menusMaxX, region.frame.maxX))
                tabsRange = StripContentView.TabsRange(offset: frame.minX - left, width: frame.width)
                frame = NSRect(x: left, y: frame.minY, width: right - left, height: frame.height)
            }
            strip.panel.content.tabsRange = tabsRange
            if strip.panel.frame != frame {
                strip.panel.setFrame(frame, display: true)
            }
            if !strip.panel.isVisible {
                strip.panel.orderFrontRegardless()
            }
        }
    }

    private func orderedWindows(_ windows: [WindowInfo]) -> [WindowInfo] {
        let byID = Dictionary(windows.map { ($0.windowID, $0) }, uniquingKeysWith: { first, _ in first })
        let ordered = TabOrdering.order(
            tracker.withFocusTimes(windows.map(\.snapshot)),
            mode: settings.order,
            firstSeen: tracker.firstSeen,
            pinnedApps: settings.pinnedApps
        )
        return ordered.compactMap { byID[$0.windowID] }
    }

    private func pillModel(for window: WindowInfo) -> PillModel {
        PillModel(
            key: String(window.windowID),
            text: window.label(settings.label),
            accessibilityText: TabLabel.accessibilityText(appName: window.appName, title: window.title),
            icon: appIcon(pid: window.pid),
            isActive: window.isFocused,
            isMinimized: window.isMinimized,
            window: window,
            action: { [weak self] in
                self?.noteFocus(window.windowID)
                WindowRaiser.raise(window)
            },
            middleClick: { WindowRaiser.close(window) }
        )
    }

    private var permissionPill: PillModel {
        PillModel(
            key: "grant-accessibility",
            text: "Grant Accessibility access",
            accessibilityText: "Grant Accessibility access. Opens setup.",
            icon: nil,
            isActive: false,
            action: { OnboardingWindowController.shared.show() }
        )
    }

    private func appIcon(pid: pid_t) -> NSImage? {
        if let cached = iconCache[pid] { return cached }
        guard let icon = NSRunningApplication(processIdentifier: pid)?.icon?.copy() as? NSImage else {
            return nil
        }
        icon.size = NSSize(width: StripLayout.iconSize, height: StripLayout.iconSize)
        iconCache[pid] = icon
        return icon
    }

    private func checkPermission() {
        let nowTrusted = AXIsProcessTrusted()
        guard nowTrusted != trusted else { return }
        trusted = nowTrusted
        strips.forEach { $0.panel.content.invalidate() }
        refresh()
    }

    // MARK: StripActions

    var hideDurations: [Int] { settings.hideDurations }

    func hideStrips(for seconds: TimeInterval) {
        hiddenUntil = Date().addingTimeInterval(seconds)
        refresh()
    }

    func isPinned(_ window: WindowInfo) -> Bool { settings.isPinned(window.appKey) }

    func togglePin(_ window: WindowInfo) { settings.togglePin(window.appKey) }

    func close(_ window: WindowInfo) {
        WindowRaiser.close(window)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.refresh() }
    }

    func minimize(_ window: WindowInfo) {
        WindowRaiser.minimize(window)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.refresh() }
    }

    func openSettings() {
        SettingsWindowController.shared.show()
    }
}

/// A minimal main menu. Accessory apps never show it, but it provides the standard key equivalents
/// (Cmd-W, Cmd-Q, Cmd-C, Cmd-V, Cmd-,) while Settings or onboarding is the key window.
enum MainMenu {
    static func make() -> NSMenu {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: AppInfo.displayName)
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(AppDelegate.openSettingsAction(_:)), keyEquivalent: ",")
        appMenu.addItem(settingsItem)
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Quit \(AppInfo.displayName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        editMenu.addItem(NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z"))
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editItem.submenu = editMenu
        main.addItem(editItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(NSMenuItem(title: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        windowItem.submenu = windowMenu
        main.addItem(windowItem)
        return main
    }
}

extension AppDelegate {
    @objc func openSettingsAction(_ sender: Any?) {
        openSettings()
    }
}
