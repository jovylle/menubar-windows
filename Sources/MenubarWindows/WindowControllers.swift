// WindowControllers.swift
// Hosts the SwiftUI Settings and onboarding views in plain NSWindows, plus the Launch at login model.
//
// Gotchas:
// - This is an accessory app (no Dock icon), so a window only comes to the front if the app activates
//   itself first. activate(ignoringOtherApps:) is deprecated on macOS 14+, so activate() is used there.
// - Windows are created once and kept (isReleasedWhenClosed = false); show() just brings them back.
// - SMAppService.mainApp only works from an .app bundle. Run as a bare binary (swift run) it fails,
//   so the toggle is disabled there and says why.

import AppKit
import ServiceManagement
import SwiftUI

enum AppActivation {
    static func bringToFront() {
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

class HostedWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let title: String
    private let makeView: () -> AnyView

    init(title: String, makeView: @escaping () -> AnyView) {
        self.title = title
        self.makeView = makeView
    }

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: makeView())
            let window = NSWindow(contentViewController: hosting)
            window.title = title
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window
        }
        AppActivation.bringToFront()
        window?.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
    }
}

final class SettingsWindowController: HostedWindowController {
    static let shared = SettingsWindowController()

    private init() {
        super.init(title: "\(AppInfo.displayName) Settings") {
            AnyView(SettingsView(settings: .shared))
        }
    }
}

final class OnboardingWindowController: HostedWindowController {
    static let shared = OnboardingWindowController()

    private init() {
        super.init(title: "Welcome to \(AppInfo.displayName)") {
            AnyView(OnboardingView(onDone: { OnboardingWindowController.shared.finish() }))
        }
    }

    func finish() {
        Settings.shared.hasCompletedOnboarding = true
        close()
    }
}

/// Launch at login through SMAppService (macOS 13+).
final class LoginItemModel: ObservableObject {
    @Published private(set) var status: SMAppService.Status = .notRegistered
    @Published private(set) var lastError: String?

    var isAvailable: Bool { AppInfo.isBundled }

    var isOn: Bool { status == .enabled || status == .requiresApproval }

    init() {
        refresh()
    }

    func refresh() {
        status = SMAppService.mainApp.status
    }

    func set(_ enabled: Bool) {
        lastError = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            lastError = error.localizedDescription
        }
        refresh()
    }

    var statusText: String {
        guard isAvailable else {
            return "Available only in the app bundle (build it with scripts/build-app.sh)."
        }
        switch status {
        case .enabled: return "On. \(AppInfo.displayName) starts when you log in."
        case .requiresApproval: return "Waiting for your approval in System Settings, General, Login Items."
        case .notRegistered: return "Off."
        case .notFound: return "macOS could not find this app. Move it to Applications and try again."
        @unknown default: return "Unknown state."
        }
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

enum AccessibilityAccess {
    private static var hasPrompted = false

    /// Asks macOS once per launch (this also lists the app in System Settings), then opens the pane.
    static func requestAndOpenSettings() {
        if !hasPrompted {
            hasPrompted = true
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }
        openSettings()
    }

    static func openSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
