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
        level = .popUpMenu
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

    /// AppKit pushes ordinary windows below the menu bar. Returning the rect unchanged lets the
    /// panel sit inside it.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
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
        // macOS lets mouse clicks fall through fully transparent window pixels. A nearly invisible
        // fill keeps the whole strip, including the few points above and below the pills and the
        // very top edge of the screen, clickable.
        layer?.backgroundColor = NSColor(white: 0, alpha: 0.01).cgColor
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

    /// A click anywhere in a pill's column counts as a click on that pill, from the very top edge of
    /// the screen down to the bottom of the bar. The pill is drawn smaller, so without this the few
    /// points above it would be dead space. The mouse stops at the screen edge, so this is what makes
    /// "slam the cursor to the top and click" work.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard bounds.contains(local) else { return nil }
        let inTrack = track.convert(local, from: self)
        let half = StripLayout.pillGap / 2
        for pill in pills where inTrack.x >= pill.frame.minX - half && inTrack.x <= pill.frame.maxX + half {
            return pill
        }
        return self
    }

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        for seconds in [10, 30, 60] {
            let item = NSMenuItem(
                title: "Hide for \(seconds) seconds",
                action: #selector(hideRequested(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = seconds
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let quit = NSMenuItem(
            title: "Quit MenubarWindows",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: ""
        )
        quit.target = NSApp
        menu.addItem(quit)
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    /// Set by the app delegate. Hides every strip for the given number of seconds.
    var onHide: ((TimeInterval) -> Void)?

    @objc private func hideRequested(_ sender: NSMenuItem) {
        onHide?(TimeInterval(sender.tag))
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

        // Center the pills when they do not fill the strip.
        var x: CGFloat = max(0, (width - contentWidth) / 2)
        for (pill, pillWidth) in zip(pills, widths) {
            pill.frame = NSRect(
                x: x,
                y: 0,
                width: pillWidth,
                height: height
            )
            x += pillWidth + gap
        }
    }
}
