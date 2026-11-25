// StripPanel.swift
// One borderless, non-activating panel per screen, pinned to the top edge inside the menu bar.
// StripContentView lays out the pills and handles right-click and horizontal scrolling.
//
// Gotchas:
// - Level .statusBar sits above the menu bar (.mainMenu). The panel covers only the free strip, so
//   clicks on the empty part of the strip are swallowed and do not reach the menu bar beneath.
// - canBecomeKey is false, so clicking a pill never takes focus from the app the user is working in.
// - Pills are rebuilt only when their keys, titles or active flags change. That avoids flicker
//   on the 0.5s refresh.

import AppKit

final class StripPanel: NSPanel {
    let content = StripContentView(frame: .zero)

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .statusBar
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        contentView = content
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class StripContentView: NSView {
    private let clip = NSView()
    private let track = NSView()
    private var pills: [PillView] = []
    private var signature = ""
    /// Horizontal scroll position, used only when the pills do not fit.
    private var scrollOffset: CGFloat = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        clip.wantsLayer = true
        clip.layer?.masksToBounds = true
        clip.autoresizingMask = [.width, .height]
        addSubview(clip)
        clip.addSubview(track)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func layout() {
        super.layout()
        clip.frame = bounds
        layoutPills()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        let quit = NSMenuItem(
            title: "Quit MenubarWindows",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: ""
        )
        quit.target = NSApp
        menu.addItem(quit)
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    override func scrollWheel(with event: NSEvent) {
        let dx = event.scrollingDeltaX
        let dy = event.scrollingDeltaY
        scrollOffset -= abs(dx) > abs(dy) ? dx : dy
        layoutPills()
    }

    func update(_ models: [PillModel]) {
        let newSignature = models
            .map { "\($0.key)|\($0.text)|\($0.isActive)" }
            .joined(separator: "\n")
        guard newSignature != signature else { return }
        signature = newSignature

        pills.forEach { $0.removeFromSuperview() }
        pills = models.map { model in
            let pill = PillView(model: model)
            track.addSubview(pill)
            return pill
        }
        layoutPills()
    }

    /// Pills take their natural width. If they do not fit, they shrink evenly to a minimum width,
    /// and any remaining overflow is reached by scrolling.
    private func layoutPills() {
        let width = bounds.width
        let height = bounds.height
        let gap = StripLayout.pillGap
        guard !pills.isEmpty else {
            track.frame = NSRect(x: 0, y: 0, width: width, height: height)
            return
        }

        let count = CGFloat(pills.count)
        var widths = pills.map { $0.naturalWidth }
        let naturalTotal = widths.reduce(0, +) + gap * (count - 1)
        if naturalTotal > width {
            let equalShare = (width - gap * (count - 1)) / count
            widths = Array(repeating: max(StripLayout.minimumPillWidth, equalShare), count: pills.count)
        }

        let contentWidth = widths.reduce(0, +) + gap * (count - 1)
        scrollOffset = min(max(0, scrollOffset), max(0, contentWidth - width))
        track.frame = NSRect(x: -scrollOffset, y: 0, width: max(width, contentWidth), height: height)

        var x: CGFloat = 0
        for (pill, pillWidth) in zip(pills, widths) {
            pill.frame = NSRect(
                x: x,
                y: (height - StripLayout.pillHeight) / 2,
                width: pillWidth,
                height: StripLayout.pillHeight
            )
            x += pillWidth + gap
        }
    }
}
