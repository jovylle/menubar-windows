// PillView.swift
// One clickable window pill: app icon plus short title as a square translucent tab flush with the top of the screen.
//
// Gotchas:
// - The strip panel never becomes key, so the pill must accept first mouse or the first click is lost.
// - The NSVisualEffectView must use state .active, otherwise it renders flat when the panel is not key.
// - hitTest returns the pill itself, so clicks on the icon or label still reach mouseDown.
// - Right-click is not handled here. It falls through the responder chain to the strip's menu.

import AppKit

struct PillModel {
    let key: String
    let text: String
    let icon: NSImage?
    let isActive: Bool
    let action: () -> Void
}

final class PillView: NSView {
    private static let font = NSFont.systemFont(ofSize: StripLayout.pillFontSize, weight: .medium)
    private static let horizontalPadding: CGFloat = 10
    private static let iconGap: CGFloat = 6

    private let background = NSVisualEffectView()
    private let highlight = NSView()
    private let iconView = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let underline = NSView()
    private let onClick: () -> Void
    /// Width this pill would take at its text's natural length.
    let naturalWidth: CGFloat

    init(model: PillModel) {
        onClick = model.action
        let textWidth = ceil((model.text as NSString).size(withAttributes: [.font: Self.font]).width)
        let iconWidth = model.icon == nil ? 0 : StripLayout.iconSize + Self.iconGap
        naturalWidth = Self.horizontalPadding * 2 + iconWidth + textWidth
        super.init(frame: .zero)
        configure(model)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private func configure(_ model: PillModel) {
        wantsLayer = true

        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.masksToBounds = true
        addSubview(background)

        // Brightens the active pill. Lives inside the effect view so it is clipped to the tab.
        highlight.wantsLayer = true
        highlight.layer?.backgroundColor = NSColor.white
            .withAlphaComponent(model.isActive ? 0.22 : 0.04).cgColor
        highlight.autoresizingMask = [.width, .height]
        background.addSubview(highlight)

        // Square tab flush with the top of the screen. The active tab gets an accent underline.
        if model.isActive {
            underline.wantsLayer = true
            underline.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
            addSubview(underline)
        }

        iconView.image = model.icon
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.isHidden = model.icon == nil
        addSubview(iconView)

        label.stringValue = model.text
        label.font = Self.font
        label.textColor = .white
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        addSubview(label)
    }

    override func layout() {
        super.layout()
        background.frame = bounds
        background.layer?.cornerRadius = 0
        underline.frame = NSRect(x: 0, y: 0, width: bounds.width, height: 2)

        var x = Self.horizontalPadding
        if !iconView.isHidden {
            iconView.frame = NSRect(
                x: x,
                y: (bounds.height - StripLayout.iconSize) / 2,
                width: StripLayout.iconSize,
                height: StripLayout.iconSize
            )
            x += StripLayout.iconSize + Self.iconGap
        }
        let labelHeight: CGFloat = 16
        label.frame = NSRect(
            x: x,
            y: (bounds.height - labelHeight) / 2,
            width: max(0, bounds.width - x - Self.horizontalPadding),
            height: labelHeight
        )
    }

    // Receive clicks on the icon and label too.
    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        onClick()
    }
}
