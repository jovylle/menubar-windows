// OnboardingView.swift
// First-launch guide, also shown whenever Accessibility is not granted. Three steps:
//   1. what the app does (a small drawn menu bar with tabs)
//   2. why Accessibility is needed, and that nothing leaves the Mac
//   3. open System Settings, with a live status that flips to granted on its own
//
// Gotchas:
// - PermissionMonitor polls AXIsProcessTrusted every second while a view holds it. There is no
//   notification for Accessibility changes.
// - When run with `swift run`, macOS grants access to the terminal app, not to this binary. The text
//   says so, because otherwise the status never flips for people testing from a terminal.

import AppKit
import Combine
import SwiftUI

final class PermissionMonitor: ObservableObject {
    /// Demo mode shows the granted state, as on a set-up Mac.
    @Published private(set) var isTrusted = DemoMode.isOn || AXIsProcessTrusted()
    private var timer: AnyCancellable?

    init() {
        timer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                let now = DemoMode.isOn || AXIsProcessTrusted()
                if self?.isTrusted != now { self?.isTrusted = now }
            }
    }
}

struct OnboardingView: View {
    let onDone: () -> Void
    @StateObject private var permission = PermissionMonitor()
    @State private var step = 0

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case 0: whatItDoes
                case 1: whyAccess
                default: grantAccess
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 36)
            .padding(.top, 28)

            Divider()
            HStack {
                Text("Step \(step + 1) of 3")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer()
                if step > 0 {
                    Button("Back") { step -= 1 }
                }
                if step < 2 {
                    Button("Continue") { step += 1 }
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button(permission.isTrusted ? "Done" : "Later") { onDone() }
                        .keyboardShortcut(permission.isTrusted ? .defaultAction : .cancelAction)
                }
            }
            .padding(16)
        }
        .frame(width: 520, height: 440)
    }

    private var whatItDoes: some View {
        VStack(spacing: 18) {
            MenuBarIllustration()
                .frame(height: 64)
                .accessibilityLabel("Illustration: a menu bar with three window tabs in the middle, one highlighted")
            Text("Your windows, in the menu bar")
                .font(.title2).bold()
            Text("\(AppInfo.displayName) puts a tab for each window on a display into the empty middle of "
                + "its menu bar. Click a tab to bring that window forward. Push the pointer to the very top "
                + "of the screen and click: the tabs reach the edge.")
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text("Right-click a tab for more: hide the strip for a moment, pin an app, close a window, or open Settings.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var whyAccess: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Why Accessibility access", systemImage: "hand.raised")
                .font(.title2.bold())
            Text("macOS only lets an app see window titles and switch windows through Accessibility. "
                + "\(AppInfo.displayName) uses it to:")
            VStack(alignment: .leading, spacing: 6) {
                Label("read the title and position of each window", systemImage: "text.alignleft")
                Label("see which window is focused", systemImage: "scope")
                Label("raise, minimize or close a window when you ask", systemImage: "macwindow.on.rectangle")
            }
            .padding(.leading, 4)
            Label("Nothing leaves your Mac. The app makes no network connections and has no analytics. "
                + "It does not need Screen Recording.", systemImage: "lock")
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
    }

    private var grantAccess: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Turn on Accessibility", systemImage: "switch.2")
                .font(.title2.bold())
            Text("Open System Settings, go to Privacy and Security, then Accessibility, and switch on "
                + "\(AppInfo.displayName). If it is not in the list, add it with the + button.")
                .fixedSize(horizontal: false, vertical: true)
            Button("Open System Settings") { AccessibilityAccess.requestAndOpenSettings() }
                .controlSize(.large)

            HStack(spacing: 10) {
                Image(systemName: permission.isTrusted ? "checkmark.circle.fill" : "hourglass")
                    .font(.title2)
                    .foregroundStyle(permission.isTrusted ? .green : .secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(permission.isTrusted ? "Access granted" : "Waiting for access…")
                        .bold()
                    Text(permission.isTrusted
                        ? "You are all set. The tabs are in your menu bar now."
                        : "This updates on its own as soon as you switch it on.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.12)))
            .accessibilityElement(children: .combine)

            if !AppInfo.isBundled {
                Text("Running from a terminal? Then macOS asks about the terminal app, not \(AppInfo.displayName).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

/// A small drawn menu bar: Apple mark, a few menu titles, three tabs (one active), status icons.
struct MenuBarIllustration: View {
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.secondary.opacity(0.18))
                HStack(spacing: 0) {
                    HStack(spacing: 10) {
                        Image(systemName: "apple.logo")
                        Text(DemoMode.isOn ? "Draftpad" : "Finder").bold()
                        Text("File")
                        Text("Edit")
                    }
                    .font(.system(size: 11))
                    .padding(.leading, 12)
                    Spacer(minLength: 8)
                    HStack(spacing: 1) {
                        tab(DemoMode.isOn ? "Draftpad" : "Mail", active: false)
                        tab(DemoMode.isOn ? "Planner" : "Notes", active: true)
                        tab(DemoMode.isOn ? "Shellbox" : "Terminal", active: false)
                    }
                    Spacer(minLength: 8)
                    HStack(spacing: 8) {
                        Image(systemName: "wifi")
                        Image(systemName: "battery.75")
                        Text("9:41")
                    }
                    .font(.system(size: 11))
                    .padding(.trailing, 12)
                }
                .frame(width: width, height: 26)
            }
        }
    }

    private func tab(_ title: String, active: Bool) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .medium))
            // Matches the default look: a brighter fill with dark text marks the active tab.
            .foregroundStyle(active ? Color(white: 0.07) : .white)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(active ? Color(white: 0.96) : Color.black.opacity(0.75))
    }
}
