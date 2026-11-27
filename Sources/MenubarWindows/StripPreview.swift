// StripPreview.swift
// The live preview at the top of Settings: three made-up windows run through the real TabOrdering and
// TabLabel functions and drawn by the real StripContentView and PillView, on a small drawn menu bar.
// Because it reuses the production code, the preview cannot drift from the strip.
//
// Gotcha: the made-up windows are chosen so every order mode gives a different order:
//   Automatic: Mail, Terminal, Notes   Recent: Terminal, Mail, Notes   A to Z: Mail, Notes, Terminal
//   Left to right: Terminal, Notes, Mail   Pinned (Notes pinned): Notes, Mail, Terminal
// - Demo mode renames them to invented apps (Draftpad, Shellbox, Planner, same order rules) with
//   generated icons, so no real app shows in screenshots.
// - The preview draws the notched layout when any screen has a notch, because that is when the picker
//   says Left and Middle. Its placement comes from the same StripAlignment.placement as the strip. Off a
//   notch, the picker has Left, Middle and Right, and the preview follows the same rule.

import AppKit
import MenubarWindowsCore
import SwiftUI

struct StripPreview: NSViewRepresentable {
    @ObservedObject var settings: Settings

    func makeNSView(context: Context) -> PreviewBarView {
        PreviewBarView()
    }

    func updateNSView(_ view: PreviewBarView, context: Context) {
        view.render(settings: settings)
    }
}

final class PreviewBarView: NSView {
    private let strip = StripContentView(frame: .zero)
    private let apple = NSImageView()
    private static let barHeight: CGFloat = 26

    private static var samples: [(WindowSnapshot, String)] { DemoMode.isOn ? demoSamples : realSamples }

    private static let demoSamples: [(WindowSnapshot, String)] = realSamples.map { sample, _ in
        let names = ["preview.mail": "Draftpad", "preview.terminal": "Shellbox", "preview.notes": "Planner"]
        let name = names[sample.appKey] ?? "Draftpad"
        let key = "demo.\(name.lowercased())"
        let titles = ["Draftpad": "Launch notes", "Shellbox": "build", "Planner": "Week"]
        return (WindowSnapshot(windowID: sample.windowID, pid: sample.pid, appKey: key, appName: name,
                               title: titles[name] ?? "", frame: sample.frame,
                               lastFocusedAt: sample.lastFocusedAt), key)
    }

    private static let realSamples: [(WindowSnapshot, String)] = [
        (WindowSnapshot(windowID: 1, pid: 1, appKey: "preview.mail", appName: "Mail", title: "Inbox",
                        frame: CGRect(x: 700, y: 100, width: 600, height: 500),
                        lastFocusedAt: Date(timeIntervalSince1970: 100)), "com.apple.mail"),
        (WindowSnapshot(windowID: 2, pid: 2, appKey: "preview.terminal", appName: "Terminal", title: "build",
                        frame: CGRect(x: 40, y: 100, width: 600, height: 500),
                        lastFocusedAt: Date(timeIntervalSince1970: 300)), "com.apple.Terminal"),
        (WindowSnapshot(windowID: 3, pid: 3, appKey: "preview.notes", appName: "Notes", title: "Groceries",
                        frame: CGRect(x: 300, y: 100, width: 600, height: 500)), "com.apple.Notes")
    ]

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.masksToBounds = true
        apple.image = NSImage(systemSymbolName: "apple.logo", accessibilityDescription: nil)
        apple.contentTintColor = .labelColor
        addSubview(apple)
        addSubview(strip)
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: Self.barHeight + 20)
    }

    override func updateLayer() {
        // A neutral bar that reads in light and dark mode; the tabs bring their own material and fill.
        layer?.backgroundColor = NSColor.windowBackgroundColor.blended(withFraction: 0.35, of: .gray)?.cgColor
    }

    override var wantsUpdateLayer: Bool { true }

    func render(settings: Settings) {
        let mode = settings.order
        let firstSeen: [UInt32: Int] = [1: 0, 2: 1, 3: 2]
        let ordered = TabOrdering.order(
            Self.samples.map(\.0),
            mode: mode,
            firstSeen: firstSeen,
            pinnedApps: mode == .pinnedFirst ? [Self.samples[2].0.appKey] : []
        )
        let iconFor = Dictionary(uniqueKeysWithValues: Self.samples.map { ($0.0.windowID, $0.1) })
        let models = ordered.map { window in
            PillModel(
                key: "preview-\(window.windowID)",
                text: TabLabel.text(appName: window.appName, title: window.title, mode: settings.label),
                accessibilityText: TabLabel.accessibilityText(appName: window.appName, title: window.title),
                icon: Self.icon(bundleID: iconFor[window.windowID] ?? ""),
                isActive: window.windowID == 2,
                action: {}
            )
        }
        var options = StripOptions.current(edge: placement.edge)
        options.topOverscan = 0
        strip.update(models, appearance: .current(inWindow: true), options: options)
        setAccessibilityLabel("Preview: tabs \(ordered.map(\.appName).joined(separator: ", ")), \(Self.samples[1].0.appName) active")
        needsLayout = true
    }

    /// The stored alignment on the preview's bar, with the same rules as MenuBarGeometry.freeStrip. The
    /// preview treats its bar as notched when any screen has a notch, which is when the picker shows Left and Middle.
    private var placement: StripPlacement.Placement {
        let notched = MenuBarGeometry.anyScreenHasNotch
        return Settings.shared.alignment.placement(pickerShowsNotchLabels: notched, screenHasNotch: notched)
    }

    override func layout() {
        super.layout()
        let barY = (bounds.height - Self.barHeight) / 2
        apple.frame = NSRect(x: 12, y: barY + 6, width: 14, height: 14)
        let available = bounds.width - 120
        let width = Settings.shared.widthMode == .automatic
            ? strip.preferredWidth(maximum: available)
            : min(available, CGFloat(Settings.shared.stripWidth) * available / 900)
        let x: CGFloat
        switch placement.edge {
        case .leading: x = Settings.shared.coverAppleMenu ? 0 : StripLayout.appleMenuInset
        case .center: x = (bounds.width - width) / 2
        case .trailing: x = bounds.width - 60 - width
        }
        let tabHeight = (Self.barHeight * CGFloat(Settings.shared.tabHeightPercent) / 100).rounded()
        strip.frame = NSRect(
            x: x.rounded(),
            y: barY + Self.barHeight - tabHeight,
            width: width.rounded(.up),
            height: tabHeight + StripLayout.topOverscan
        )
    }

    private static var iconCache: [String: NSImage] = [:]

    private static func icon(bundleID: String) -> NSImage? {
        if DemoMode.isOn { return DemoMode.icon(appKey: bundleID) }
        if let cached = iconCache[bundleID] { return cached }
        let image: NSImage?
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            image = NSWorkspace.shared.icon(forFile: url.path).copy() as? NSImage
        } else {
            image = NSImage(systemSymbolName: "macwindow", accessibilityDescription: nil)
        }
        image?.size = NSSize(width: StripLayout.iconSize, height: StripLayout.iconSize)
        iconCache[bundleID] = image
        return image
    }
}
