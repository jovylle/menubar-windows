// PillView.swift
// One clickable tab: app icon plus short label, drawn as a translucent tab. The Settings preview uses
// this same view, so the preview cannot drift from the real strip.
//
// Gotchas:
// - The strip panel never becomes key, so the pill must accept first mouse or the first click is lost.
// - The NSVisualEffectView must use state .active, otherwise it renders flat when the panel is not key.
// - hitTest returns the pill itself, so clicks on the icon or label still reach mouseDown.
// - Right-click is not handled here. It falls through the responder chain to the strip's menu, which
//   finds the pill under the pointer itself.
// - Middle-click (button 2) closes the window through onMiddleClick.
// - Square style is flush with the top of the screen (full bar height): flared top, rounded bottom corners
//   (an upside-down browser tab, drawn by tabPath as a layer mask). Rounded style
//   is inset a few points and keeps a corner radius; the column above it is still clickable because the
//   strip's hitTest maps the whole column to the pill.
// - In the Settings preview the panel is a normal window, so the effect view blends within the window
//   (PillAppearance.inWindow) instead of behind it.

import AppKit
import MenubarWindowsCore

struct PillAppearance: Equatable {
    var style: TabStyle
    var theme: ColorTheme
    var indicator: ActiveIndicator
    var accent: NSColor
    var inWindow = false

    static func current(inWindow: Bool = false) -> PillAppearance {
        let settings = Settings.shared
        return PillAppearance(
            style: settings.style,
            theme: settings.theme,
            indicator: settings.indicator,
            accent: settings.accentColor,
            inWindow: inWindow
        )
    }

    /// Distinguishes appearances for the strip's rebuild check.
    var signature: String {
        let rgb = accent.usingColorSpace(.sRGB)
        let color = rgb.map { String(format: "%.3f,%.3f,%.3f", $0.redComponent, $0.greenComponent, $0.blueComponent) } ?? "?"
        return "\(style.rawValue)|\(theme.rawValue)|\(indicator.rawValue)|\(color)|\(inWindow)"
    }
}

struct PillModel {
    let key: String
    /// Visible label. Empty means icon only.
    let text: String
    /// Full description for VoiceOver and the tooltip.
    let accessibilityText: String
    let icon: NSImage?
    let isActive: Bool
    var isMinimized = false
    /// The window behind this pill; nil for the "+N" overflow tab and the permission pill.
    var window: WindowInfo?
    let action: () -> Void
    var middleClick: (() -> Void)?
}

final class PillView: NSView {
    private static let font = NSFont.systemFont(ofSize: StripLayout.pillFontSize, weight: .medium)
    private static let horizontalPadding: CGFloat = 10
    private static let iconGap: CGFloat = 6
    private static let roundedInset: CGFloat = 3
    private static let roundedRadius: CGFloat = 6
    /// Square style: radius of the bottom corners.
    private static let bottomRadius: CGFloat = 9
    /// Square style: how far the top of the tab flares out past its body, like a browser tab turned
    /// upside down. The body is narrower than the frame by this much on each side.
    static let flareRadius: CGFloat = 8

    private let background = NSVisualEffectView()
    private let highlight = NSView()
    private let iconView = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let underline = NSView()
    private let divider = NSView()
    /// A faint line on the left body edge, between two neighbouring inactive tabs of the same color.
    var showsDivider = false {
        didSet { divider.isHidden = !showsDivider }
    }
    private let appearanceStyle: PillAppearance
    private let onClick: () -> Void
    private let onMiddleClick: (() -> Void)?
    let model: PillModel
    /// Width this pill would take at its label's natural length.
    let naturalWidth: CGFloat
    /// Width with the label hidden (icon only). Equals naturalWidth when there is no icon.
    let compactWidth: CGFloat

    /// Hides the label so a crowded strip still fits. Ignored when the pill has no icon.
    var isCompact = false {
        didSet {
            guard oldValue != isCompact else { return }
            needsLayout = true
        }
    }

    init(model: PillModel, appearance: PillAppearance) {
        self.model = model
        appearanceStyle = appearance
        onClick = model.action
        onMiddleClick = model.middleClick
        let textWidth = model.text.isEmpty
            ? 0 : ceil((model.text as NSString).size(withAttributes: [.font: Self.font]).width)
        let iconWidth = model.icon == nil ? 0 : StripLayout.iconSize
        let gap = (model.icon != nil && textWidth > 0) ? Self.iconGap : 0
        let flare = appearance.style == .square ? Self.flareRadius : 0
        naturalWidth = (Self.horizontalPadding + flare) * 2 + iconWidth + gap + textWidth
        compactWidth = model.icon == nil ? naturalWidth : (Self.horizontalPadding + flare) * 2 + iconWidth
        super.init(frame: .zero)
        configure()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private var flare: CGFloat { appearanceStyle.style == .square ? Self.flareRadius : 0 }

    /// True when dropping the label still leaves something to show (an icon).
    var isCompactable: Bool { model.icon != nil && !model.text.isEmpty }

    private var showsLabel: Bool {
        !model.text.isEmpty && !(isCompact && model.icon != nil)
    }

    private func configure() {
        wantsLayer = true

        background.material = .menu
        background.blendingMode = appearanceStyle.inWindow ? .withinWindow : .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.masksToBounds = true
        addSubview(background)

        // Brightens the active pill. Lives inside the effect view so it is clipped to the tab.
        highlight.wantsLayer = true
        highlight.autoresizingMask = [.width, .height]
        background.addSubview(highlight)

        // Accent underline on the active tab. Also inside the effect view, so rounded corners clip it.
        if model.isActive && appearanceStyle.indicator.showsUnderline {
            underline.wantsLayer = true
            underline.layer?.backgroundColor = appearanceStyle.accent.cgColor
            background.addSubview(underline)
        }

        iconView.image = model.icon
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.isHidden = model.icon == nil
        addSubview(iconView)

        label.stringValue = model.text
        label.font = Self.font
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        addSubview(label)

        divider.wantsLayer = true
        divider.isHidden = true
        addSubview(divider)
        applyColors()

        // Minimized windows get a dimmed icon. The label keeps full contrast (see TabPalette), and the
        // tooltip and VoiceOver say "minimized", so it is not conveyed by brightness alone.
        iconView.alphaValue = model.isMinimized ? CGFloat(TabPalette.minimizedIconAlpha) : 1

        let description = model.isMinimized ? "\(model.accessibilityText) (minimized)" : model.accessibilityText
        toolTip = description
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(description)
        if model.isActive {
            setAccessibilityValue("Active window")
        }
    }

    private var isLightAppearance: Bool {
        effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .aqua
    }

    /// Colors come from TabPalette (MenubarWindowsCore), whose tests keep every label at 4.5:1 or more
    /// over its tab in light, dark and Pure black, including over the worst backdrop.
    private func applyColors() {
        let colors = TabPalette.colors(
            pureBlack: appearanceStyle.theme == .black,
            light: isLightAppearance,
            active: model.isActive,
            activeFill: appearanceStyle.indicator.showsFill
        )
        let text = NSColor(white: colors.text.white, alpha: colors.text.alpha)
        highlight.layer?.backgroundColor = NSColor(white: colors.fill.white, alpha: colors.fill.alpha).cgColor
        label.textColor = text
        divider.layer?.backgroundColor = text.withAlphaComponent(0.22).cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColors()
    }

    override func layout() {
        super.layout()
        let rounded = appearanceStyle.style == .rounded
        let inset = rounded ? Self.roundedInset : 0
        background.frame = bounds.insetBy(dx: rounded ? 1 : 0, dy: inset)
        // Square style: the tab is flush with the top of the screen. Its body is narrower than the
        // frame, its bottom corners are rounded, and its top flares out into the screen edge, which
        // is a browser tab turned upside down. Rounded style: all four corners, inset. The mask path
        // uses layer coordinates, where y grows upward (the bottom edge is y = 0).
        if rounded {
            background.layer?.mask = nil
            background.layer?.cornerRadius = Self.roundedRadius
            background.layer?.maskedCorners = [
                .layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner
            ]
        } else {
            background.layer?.cornerRadius = 0
            let mask = CAShapeLayer()
            mask.frame = background.bounds
            mask.path = Self.tabPath(size: background.bounds.size, flare: Self.flareRadius, radius: Self.bottomRadius)
            background.layer?.mask = mask
        }
        highlight.frame = background.bounds
        divider.frame = NSRect(x: flare - 0.5, y: 7, width: 1, height: max(0, bounds.height - 14))
        underline.frame = NSRect(x: 0, y: 0, width: background.bounds.width, height: 2)

        let showLabel = showsLabel
        label.isHidden = !showLabel
        // Icon-only pills center the icon; labelled pills start at the padding.
        let side = Self.horizontalPadding + flare
        var x = showLabel ? side : max(side, (bounds.width - StripLayout.iconSize) / 2)
        if !iconView.isHidden {
            iconView.frame = NSRect(
                x: x,
                y: (bounds.height - StripLayout.iconSize) / 2,
                width: StripLayout.iconSize,
                height: StripLayout.iconSize
            )
            x += StripLayout.iconSize + Self.iconGap
        } else if !model.text.isEmpty, bounds.width > naturalWidth {
            // Text-only pills (the "+N" tab) center their label.
            x = (bounds.width - (naturalWidth - side * 2)) / 2
        }
        let labelHeight: CGFloat = 16
        label.frame = NSRect(
            x: x,
            y: (bounds.height - labelHeight) / 2,
            width: max(0, bounds.width - x - side),
            height: labelHeight
        )
    }

    /// The upside-down browser tab: flat top that flares out at both ends, rounded bottom corners.
    static func tabPath(size: CGSize, flare r: CGFloat, radius rb: CGFloat) -> CGPath {
        let w = size.width
        let h = size.height
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: h))
        // Left flare, a concave quarter circle from the top edge down into the body.
        path.addArc(center: CGPoint(x: 0, y: h - r), radius: r, startAngle: .pi / 2, endAngle: 0, clockwise: true)
        path.addLine(to: CGPoint(x: r, y: rb))
        path.addArc(center: CGPoint(x: r + rb, y: rb), radius: rb, startAngle: .pi, endAngle: 3 * .pi / 2, clockwise: false)
        path.addLine(to: CGPoint(x: w - r - rb, y: 0))
        path.addArc(center: CGPoint(x: w - r - rb, y: rb), radius: rb, startAngle: 3 * .pi / 2, endAngle: 0, clockwise: false)
        path.addLine(to: CGPoint(x: w - r, y: h - r))
        path.addArc(center: CGPoint(x: w, y: h - r), radius: r, startAngle: .pi, endAngle: .pi / 2, clockwise: true)
        path.closeSubpath()
        return path
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

    override func otherMouseDown(with event: NSEvent) {
        if event.buttonNumber == 2, let onMiddleClick {
            onMiddleClick()
        } else {
            super.otherMouseDown(with: event)
        }
    }

    override func accessibilityPerformPress() -> Bool {
        onClick()
        return true
    }
}
