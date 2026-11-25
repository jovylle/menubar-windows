// AppDelegate.swift
// Owns one StripPanel per screen and three timers:
//   1.0s  geometry: free strip frame and show/hide
//   0.5s  windows: pill contents for each screen
//   2.0s  Accessibility permission poll
// Panels are rebuilt on NSApplication.didChangeScreenParametersNotification. Everything is refreshed
// when another app activates.
//
// Gotchas:
// - Without Accessibility permission the window list is empty. Screen 0 shows one
//   "Grant Accessibility access" pill instead.
// - The prompt option is passed only once at launch. Repeating it would reopen the system dialog.

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private struct ScreenStrip {
        let screen: NSScreen
        let panel: StripPanel
    }

    private var strips: [ScreenStrip] = []
    private var trusted = false
    private var timers: [Timer] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        trusted = AXIsProcessTrustedWithOptions(options)

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

        timers = [
            Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                self?.refreshGeometry()
            },
            Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                self?.refreshWindows()
            },
            Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
                self?.checkPermission()
            }
        ]

        rebuildPanels()
    }

    @objc private func screensChanged(_ notification: Notification) {
        rebuildPanels()
    }

    @objc private func appActivated(_ notification: Notification) {
        refreshAll()
        // The new app's menu titles reach Accessibility a moment after activation, so measure again.
        for delay in [0.15, 0.4] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.refreshGeometry()
            }
        }
    }

    private func rebuildPanels() {
        strips.forEach { $0.panel.orderOut(nil) }
        strips = NSScreen.screens.map { ScreenStrip(screen: $0, panel: StripPanel()) }
        refreshAll()
    }

    private func refreshAll() {
        refreshGeometry()
        refreshWindows()
    }

    private func refreshGeometry() {
        for strip in strips {
            let free: FreeStrip? = MenuBarGeometry.freeStrip(on: strip.screen)
            guard let free else {
                strip.panel.orderOut(nil)
                continue
            }
            if strip.panel.frame != free.frame {
                strip.panel.setFrame(free.frame, display: true)
            }
            if !strip.panel.isVisible {
                strip.panel.orderFrontRegardless()
            }
        }
    }

    private func refreshWindows() {
        let windows = trusted ? WindowProvider.allWindows() : []
        for (index, strip) in strips.enumerated() where strip.panel.isVisible {
            let models: [PillModel]
            if !trusted {
                models = index == 0 ? [Self.permissionPill] : []
            } else {
                models = WindowProvider.windows(on: strip.screen, in: windows).map { window in
                    self.pillModel(for: window)
                }
            }
            strip.panel.content.update(models)
        }
    }

    private func pillModel(for window: WindowInfo) -> PillModel {
        PillModel(
            key: String(window.windowID),
            text: window.displayText,
            icon: appIcon(pid: window.pid),
            isActive: window.isFocused,
            action: { WindowRaiser.raise(window) }
        )
    }

    private static var permissionPill: PillModel {
        PillModel(
            key: "grant-accessibility",
            text: "Grant Accessibility access",
            icon: nil,
            isActive: false,
            action: { openAccessibilitySettings() }
        )
    }

    private func appIcon(pid: pid_t) -> NSImage? {
        guard let icon = NSRunningApplication(processIdentifier: pid)?.icon?.copy() as? NSImage else {
            return nil
        }
        icon.size = NSSize(width: StripLayout.iconSize, height: StripLayout.iconSize)
        return icon
    }

    private func checkPermission() {
        let nowTrusted = AXIsProcessTrusted()
        guard nowTrusted != trusted else { return }
        trusted = nowTrusted
        refreshAll()
    }

    private static func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
