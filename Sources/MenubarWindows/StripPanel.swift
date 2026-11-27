// StripPanel.swift
// One borderless, non-activating panel per screen, pinned to the top edge inside the menu bar.
// StripContentView lays out the pills and handles right-click, middle-click and horizontal scrolling.
//
// Gotchas:
// - Level .popUpMenu sits above the menu bar (.mainMenu) and its status items. The panel covers only
//   the strip, so clicks on any empty part of it are swallowed and do not reach the menu bar beneath.
//   In Automatic width mode the panel is trimmed to the tabs, so there is almost no empty part.
// - constrainFrameRect is overridden to return the rect unchanged. Without it AppKit pushes the panel
//   below the menu bar.
// - canBecomeKey is false, so clicking a pill never takes focus from the app the user is working in.
// - Pills are rebuilt only when their keys, labels, active flags or the appearance change. That avoids
//   flicker on the 0.5s refresh.
// - The content view's layer has a 0.01-alpha fill. macOS lets clicks fall through fully transparent
//   window pixels; the near-invisible fill keeps the strip, including the top overscan, clickable.
// - Drag to reorder: the dragged pill follows the pointer (track coordinates, x only) and the others
//   slide to the drop slot. The drop index is found from the pill centers at drag start, not from the
//   sliding frames, so the slot does not flicker at a boundary. The drop calls StripActions.moveTab.
//   Overflow ("+N") and the permission pill are never dragged or drop targets.
// - update() does not rebuild pills while a drag is running; the pill being dragged must stay in place.

import AppKit
import MenubarWindowsCore

/// Actions the strip's context menu needs. Implemented by AppDelegate.
protocol StripActions: AnyObject {
    var hideDurations: [Int] { get }
    func hideStrips(for seconds: TimeInterval)
    func isPinned(_ window: WindowInfo) -> Bool
    func togglePin(_ window: WindowInfo)
    func close(_ window: WindowInfo)
    func minimize(_ window: WindowInfo)
    func openSettings()
    /// A tab was dropped at a new position. `shown` is the window IDs of the visible tabs, in their
    /// current order; `from` and `to` are indices into it.
    func moveTab(from: Int, to: Int, shown: [UInt32])
}

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
        setAccessibilityLabel("\(AppInfo.displayName) window tabs")
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// AppKit pushes ordinary windows below the menu bar. Returning the rect unchanged lets the
    /// panel sit inside it.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

/// Layout options that come from Settings, plus the screen's edge for the tabs.
struct StripOptions: Equatable {
    var shrinkWhenCrowded = true
    /// The edge the tabs sit against inside the strip. It comes from the screen's placement (StripPlacement),
    /// not from the stored alignment, because the same stored value can mean different things per screen.
    var edge: StripPlacement.Edge = .center
    var equalWidth = true
    var maxTabWidth: CGFloat = 220
    /// Space above the pills that belongs to the panel but not the drawn tab (the top overscan).
    var topOverscan: CGFloat = StripLayout.topOverscan

    /// - Parameter edge: the tabs' edge on the screen the strip is on (`FreeStrip.anchor`).
    static func current(edge: StripPlacement.Edge) -> StripOptions {
        StripOptions(
            shrinkWhenCrowded: Settings.shared.shrinkWhenCrowded,
            edge: edge,
            equalWidth: Settings.shared.equalTabWidth,
            maxTabWidth: CGFloat(Settings.shared.maxTabWidth)
        )
    }
}

final class StripContentView: NSView {
    private let clip = NSView()
    private let track = NSView()
    private(set) var pills: [PillView] = []
    private var overflowModels: [PillModel] = []
    private var signature = ""
    private var pillAppearance = PillAppearance.current()
    private var options = StripOptions()
    /// Horizontal scroll position, used only when the pills do not fit.
    private var scrollOffset: CGFloat = 0
    /// The tab being dragged, if any.
    private var drag: Drag?

    private struct Drag {
        /// Index of the dragged pill in `pills`.
        let index: Int
        /// Distance from the pill's left edge to the pointer when the drag began.
        let grabOffset: CGFloat
        /// Pill frames when the drag began. The drop slot is computed from these, not from the sliding frames.
        let startFrames: [CGRect]
        /// Index where the pill will land when dropped.
        var to: Int
    }

    weak var actions: StripActions?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        // macOS lets mouse clicks fall through fully transparent window pixels. A nearly invisible
        // fill keeps the whole strip, including the few points above and below the pills and the
        // very top edge of the screen, clickable.
        layer?.backgroundColor = NSColor(white: 0, alpha: 0.01).cgColor
        clip.wantsLayer = true
        clip.layer?.masksToBounds = true
        addSubview(clip)
        clip.addSubview(track)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Window tabs")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    var isEmpty: Bool { pills.isEmpty }

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
        return pill(atLocal: local) ?? self
    }

    private func pill(atLocal local: NSPoint) -> PillView? {
        let inTrack = track.convert(local, from: self)
        // Square tabs overlap in their flared corners, so match on the tab bodies first. The outer
        // flares of the first and last tab fall back to the whole frame.
        let flare = pillAppearance.style == .square ? PillView.flareRadius : 0
        let half = max(0, gap) / 2
        return pills.first { inTrack.x >= $0.frame.minX + flare - half && inTrack.x < $0.frame.maxX - flare + half }
            ?? pills.first { inTrack.x >= $0.frame.minX && inTrack.x <= $0.frame.maxX }
    }

    /// Space between neighbouring tabs. Square tabs overlap by their two flares, so their bodies touch
    /// and the flared corners merge (no gap in the bar between them).
    private var gap: CGFloat {
        pillAppearance.style == .rounded
            ? StripLayout.roundedPillGap
            : -2 * PillView.flareRadius
    }

    // MARK: Menus

    override func rightMouseDown(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        let window = pill(atLocal: local)?.model.window
        NSMenu.popUpContextMenu(contextMenu(for: window), with: event, for: self)
    }

    /// Demo mode (`-mw.demoMenu`): opens the menu a right-click on tab `index` opens, at the tab's
    /// center. The event is built in-process and handed to AppKit; nothing is posted to the system.
    func showContextMenu(forTabAt index: Int) {
        guard pills.indices.contains(index), let window else { return }
        let pill = pills[index]
        let point = convert(NSPoint(x: pill.frame.midX - 20, y: pill.frame.midY), from: track)
        guard let event = NSEvent.mouseEvent(
            with: .rightMouseDown, location: convert(point, to: nil), modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        ) else { return }
        NSMenu.popUpContextMenu(contextMenu(for: pill.model.window), with: event, for: self)
    }

    private func contextMenu(for window: WindowInfo?) -> NSMenu {
        let menu = NSMenu()
        for seconds in actions?.hideDurations ?? Settings.Defaults.hideDurations {
            menu.addItem(item("Hide for \(Self.describe(seconds: seconds))", #selector(hideRequested(_:)), tag: seconds))
        }
        if let window {
            menu.addItem(.separator())
            let pinned = actions?.isPinned(window) ?? false
            let pin = item(pinned ? "Unpin \(window.appName)" : "Pin \(window.appName) to the front", #selector(pinRequested(_:)))
            pin.representedObject = WindowBox(window)
            menu.addItem(pin)
            let close = item("Close window", #selector(closeRequested(_:)))
            close.representedObject = WindowBox(window)
            menu.addItem(close)
            if !window.isMinimized {
                let minimize = item("Minimize window", #selector(minimizeRequested(_:)))
                minimize.representedObject = WindowBox(window)
                menu.addItem(minimize)
            }
        }
        menu.addItem(.separator())
        menu.addItem(item("Settings…", #selector(settingsRequested(_:))))
        let quit = NSMenuItem(
            title: "Quit \(AppInfo.displayName)",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: ""
        )
        quit.target = NSApp
        menu.addItem(quit)
        return menu
    }

    static func describe(seconds: Int) -> String {
        if seconds >= 60, seconds % 60 == 0 {
            let minutes = seconds / 60
            return minutes == 1 ? "1 minute" : "\(minutes) minutes"
        }
        return seconds == 1 ? "1 second" : "\(seconds) seconds"
    }

    private func item(_ title: String, _ action: Selector, tag: Int = 0) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.tag = tag
        return item
    }

    private final class WindowBox {
        let window: WindowInfo
        init(_ window: WindowInfo) { self.window = window }
    }

    @objc private func hideRequested(_ sender: NSMenuItem) {
        actions?.hideStrips(for: TimeInterval(sender.tag))
    }

    @objc private func pinRequested(_ sender: NSMenuItem) {
        guard let box = sender.representedObject as? WindowBox else { return }
        actions?.togglePin(box.window)
    }

    @objc private func closeRequested(_ sender: NSMenuItem) {
        guard let box = sender.representedObject as? WindowBox else { return }
        actions?.close(box.window)
    }

    @objc private func minimizeRequested(_ sender: NSMenuItem) {
        guard let box = sender.representedObject as? WindowBox else { return }
        actions?.minimize(box.window)
    }

    @objc private func settingsRequested(_ sender: NSMenuItem) {
        actions?.openSettings()
    }

    /// The "+N" tab: a menu of the windows that did not get a tab.
    private func showOverflowMenu(from anchor: PillView) {
        let menu = NSMenu()
        for model in overflowModels {
            let entry = NSMenuItem(title: model.accessibilityText, action: #selector(overflowChosen(_:)), keyEquivalent: "")
            entry.target = self
            entry.image = model.icon
            entry.state = model.isActive ? .on : .off
            entry.representedObject = ActionBox(model.action)
            menu.addItem(entry)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: -2), in: anchor)
    }

    private final class ActionBox {
        let action: () -> Void
        init(_ action: @escaping () -> Void) { self.action = action }
    }

    @objc private func overflowChosen(_ sender: NSMenuItem) {
        (sender.representedObject as? ActionBox)?.action()
    }

    // MARK: Content

    override func scrollWheel(with event: NSEvent) {
        let dx = event.scrollingDeltaX
        let dy = event.scrollingDeltaY
        scrollOffset -= abs(dx) > abs(dy) ? dx : dy
        layoutPills()
    }

    /// Forces the next update to rebuild every pill (after an appearance change).
    func invalidate() {
        signature = ""
    }

    /// - Parameters:
    ///   - models: the tabs to show, in order.
    ///   - overflow: windows that did not get a tab. When non-empty a trailing "+N" tab opens a menu.
    func update(
        _ models: [PillModel],
        overflow: [PillModel] = [],
        appearance: PillAppearance = .current(),
        options: StripOptions
    ) {
        let newSignature = (models + overflow)
            .map { "\($0.key)|\($0.text)|\($0.isActive)|\($0.isMinimized)" }
            .joined(separator: "\n")
            + "#\(overflow.count)#\(appearance.signature)#\(options.shrinkWhenCrowded)#\(options.edge.rawValue)#\(options.equalWidth)#\(options.maxTabWidth)"
        overflowModels = overflow
        // A rebuild would drop the pill under the pointer mid-drag. The strip updates after the drop.
        guard drag == nil, newSignature != signature else { return }
        signature = newSignature
        self.pillAppearance = appearance
        self.options = options

        pills.forEach { $0.removeFromSuperview() }
        var all = models
        if !overflow.isEmpty {
            // The overflow action needs the pill view to anchor its menu, so it is wired below.
            all.append(PillModel(
                key: "overflow",
                text: "+\(overflow.count)",
                accessibilityText: "\(overflow.count) more windows",
                icon: nil,
                isActive: overflow.contains(where: \.isActive),
                action: {}
            ))
        }
        let draggable = actions != nil && all.filter { $0.window != nil }.count >= 2
        pills = all.map { model in
            let pill: PillView
            if model.key == "overflow" {
                weak var box: PillView?
                let wired = PillModel(
                    key: model.key, text: model.text, accessibilityText: model.accessibilityText,
                    icon: nil, isActive: model.isActive,
                    action: { [weak self] in if let self, let box { self.showOverflowMenu(from: box) } }
                )
                pill = PillView(model: wired, appearance: appearance)
                box = pill
            } else {
                pill = PillView(model: model, appearance: appearance)
                pill.isDraggable = draggable && model.window != nil
            }
            pill.onDrag = { [weak self] pill, phase, point in self?.handleDrag(pill, phase, point) }
            track.addSubview(pill)
            return pill
        }
        for (index, pill) in pills.enumerated() {
            pill.showsDivider = index > 0 && !pill.model.isActive && !pills[index - 1].model.isActive
        }
        // The active tab is drawn last so its flared corners are not covered by a neighbour.
        if let active = pills.first(where: { $0.model.isActive }) {
            track.addSubview(active, positioned: .above, relativeTo: nil)
        }
        layoutPills()
    }

    // MARK: Drag to reorder

    private func handleDrag(_ pill: PillView, _ phase: PillDragPhase, _ point: NSPoint) {
        switch phase {
        case .began: beginDrag(pill, at: point)
        case .changed: updateDrag(to: point)
        case .ended: endDrag()
        }
    }

    private func beginDrag(_ pill: PillView, at point: NSPoint) {
        guard drag == nil, let index = pills.firstIndex(where: { $0 === pill }) else { return }
        let pointer = track.convert(point, from: nil)
        drag = Drag(
            index: index,
            grabOffset: pointer.x - pill.frame.minX,
            startFrames: pills.map(\.frame),
            to: index
        )
        // Lift the tab: on top of its neighbours and slightly see-through.
        track.addSubview(pill, positioned: .above, relativeTo: nil)
        pill.alphaValue = 0.85
    }

    private func updateDrag(to point: NSPoint) {
        guard var current = drag, pills.indices.contains(current.index) else { return }
        let pill = pills[current.index]
        let pointer = track.convert(point, from: nil)
        // Keep the dragged tab inside the row of tabs.
        let lower = current.startFrames.map(\.minX).min() ?? 0
        let upper = current.startFrames.map(\.maxX).max() ?? 0
        let x = min(max(pointer.x - current.grabOffset, lower), max(lower, upper - pill.frame.width))
        pill.frame.origin.x = x

        // The drop slot: how many other real tabs start left of the dragged tab's center.
        let center = x + pill.frame.width / 2
        let others = pills.indices.filter { $0 != current.index && pills[$0].model.window != nil }
        current.to = others.filter { current.startFrames[$0].midX < center }.count
        drag = current
        layoutPills()
    }

    private func endDrag() {
        guard let finished = drag else { return }
        drag = nil
        if pills.indices.contains(finished.index) {
            pills[finished.index].alphaValue = 1
        }
        layoutPills()
        guard finished.to != finished.index else { return }
        let shown = pills.compactMap { $0.model.window?.windowID }
        actions?.moveTab(from: finished.index, to: finished.to, shown: shown)
    }

    /// Width the pills need, given at most `maximum`. Used by Automatic width mode to trim the panel.
    func preferredWidth(maximum: CGFloat) -> CGFloat {
        guard !pills.isEmpty else { return 0 }
        if let equal = equalWidths(available: maximum) { return total(equal.widths) }
        let natural = total(pills.map(\.naturalWidth))
        if natural <= maximum { return natural }
        if options.shrinkWhenCrowded {
            let compact = total(pills.map { $0.isCompactable ? $0.compactWidth : $0.naturalWidth })
            if compact <= maximum { return compact }
        }
        return maximum
    }

    /// Equal tab widths: every window tab gets the same width, the tabs share the available space, and
    /// a tab never grows past the maximum width. The "+N" tab keeps its natural width. Returns nil when
    /// equal widths are off or the strip only holds the permission pill.
    private func equalWidths(available: CGFloat) -> (widths: [CGFloat], compact: Bool)? {
        guard options.equalWidth, !pills.contains(where: { $0.model.key == "grant-accessibility" }) else { return nil }
        let tabs = pills.filter { $0.model.key != "overflow" }
        guard !tabs.isEmpty else { return nil }
        let overflow = pills.first { $0.model.key == "overflow" }
        let reserved = overflow.map { $0.naturalWidth + gap } ?? 0
        let tabWidth = StripFill.equalTabWidth(
            available: available,
            reserved: reserved,
            gap: gap,
            count: tabs.count,
            maximum: options.maxTabWidth,
            minimum: StripLayout.minimumPillWidth,
            fills: StripFill.fillsRegion(tabCount: tabs.count)
        )
        let compact = options.shrinkWhenCrowded && tabWidth < StripLayout.equalCompactBelow
        let widths = pills.map { $0.model.key == "overflow" ? $0.naturalWidth : tabWidth }
        return (widths, compact)
    }

    private func total(_ widths: [CGFloat]) -> CGFloat {
        widths.reduce(0, +) + gap * CGFloat(max(0, widths.count - 1))
    }

    /// Pills take their natural width. If they do not fit, they first drop their labels (when "Shrink
    /// to icon-only when crowded" is on), then shrink evenly to a minimum width, and any remaining
    /// overflow is reached by scrolling.
    private func layoutPills() {
        let width = bounds.width
        let height = bounds.height
        guard !pills.isEmpty else {
            track.frame = NSRect(x: 0, y: 0, width: width, height: height)
            return
        }

        var compact = false
        var widths = pills.map(\.naturalWidth)
        if let equal = equalWidths(available: width) {
            widths = equal.widths
            compact = equal.compact
        } else if total(widths) > width + 0.5, options.shrinkWhenCrowded {
            compact = true
            widths = pills.map { $0.isCompactable ? $0.compactWidth : $0.naturalWidth }
        }
        if equalWidths(available: width) == nil, total(widths) > width + 0.5 {
            let count = CGFloat(pills.count)
            let equalShare = (width - gap * (count - 1)) / count
            widths = Array(repeating: max(StripLayout.minimumPillWidth, equalShare), count: pills.count)
        }
        for pill in pills { pill.isCompact = compact }

        let contentWidth = total(widths)
        scrollOffset = min(max(0, scrollOffset), max(0, contentWidth - width))
        track.frame = NSRect(x: -scrollOffset, y: 0, width: max(width, contentWidth), height: height)

        var x: CGFloat
        switch options.edge {
        case .leading: x = 0
        case .center: x = max(0, (width - contentWidth) / 2)
        case .trailing: x = max(0, width - contentWidth)
        }
        // Display order. While dragging, the dragged tab is taken out and put back at its drop slot, so
        // the others slide aside. The dragged tab keeps the frame the pointer gave it.
        var slots = Array(pills.indices)
        if let drag, slots.indices.contains(drag.index) {
            slots.remove(at: drag.index)
            slots.insert(drag.index, at: min(drag.to, slots.count))
        }
        for index in slots {
            if index != drag?.index {
                let frame = NSRect(x: x, y: 0, width: widths[index], height: height - options.topOverscan)
                place(pills[index], frame, animated: drag != nil)
            }
            x += widths[index] + gap
        }
    }

    /// Slides a tab to its slot. Animated only while a drag moves the others.
    private func place(_ pill: PillView, _ frame: NSRect, animated: Bool) {
        guard animated, pill.frame != frame else {
            pill.frame = frame
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            pill.animator().frame = frame
        }
    }
}
