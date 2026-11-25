// MenuBarGeometry.swift
// Computes the strip region inside the menu bar for one screen: the most the strip may cover, between
// the Apple and app-name menus (left) and the status icons (right). AppDelegate then trims the panel
// to the tabs in Automatic width mode (see FreeStrip.panelFrame).
//
// Gotchas:
// - Coordinate spaces: Cocoa (NSScreen, NSPanel) is bottom-left origin, measured from the primary
//   screen. AX and CGWindowList are top-left origin on the same global plane. Convert with
//   cocoaRect(fromTopLeft:): cocoaY = primaryScreen.frame.maxY - topLeftMaxY.
// - The menu bar is only reserved on the screen that shows it, and NSScreen.visibleFrame can report no
//   reserved height on an external display that does have one. A screen counts as having a menu bar
//   when the system reserves one or the frontmost app's menu titles sit on it.
// - AX reports menu titles for one display only. Their offset is measured on that owner display and
//   translated to the requested screen (every display draws the titles at the same offset).
// - The region is anchored to the middle of the bar (the configured strip width wide), or ends at the
//   notch on notched screens (auxiliaryTopLeftArea). The frontmost app's menus are ignored on purpose;
//   "Hide for ..." reaches them. Only the Apple menu and the app name (minimumLeftInset) are kept clear.
// - Status icons are windows at level 25 (status bar) inside the bar band. The region's right edge is
//   pulled back to stay clear of them, sliding left to keep the width.
// - The panel extends topOverscan points ABOVE the screen's top edge, so a click with the pointer
//   pushed against the very top still lands on a tab.

import AppKit
import ApplicationServices

enum StripLayout {
    /// Default strip width (the maximum in Automatic width mode). The user setting overrides it.
    static let stripWidth: CGFloat = 560
    /// Gap between the notch and the strip's right edge.
    static let notchGap: CGFloat = 12
    /// Status item windows are never wider than this. Wider status-level windows are ignored.
    static let maxStatusItemWidth: CGFloat = 160
    /// The panel extends this far above the top edge of the screen (a negative top margin), so a click
    /// with the pointer pushed against the very top still lands on a tab.
    static let topOverscan: CGFloat = 6
    /// The strip never starts closer than this to the left screen edge (keeps the Apple menu usable).
    static let minimumLeftInset: CGFloat = 130
    /// Left placement starts this far from the screen edge, which keeps the Apple menu clear.
    static let leftPlacementInset: CGFloat = 42
    /// Gap between the strip and the leftmost status icon.
    static let statusGap: CGFloat = 12
    /// Below this width the strip is hidden.
    static let minimumStripWidth: CGFloat = 120
    static let pillHeight: CGFloat = 22
    static let pillFontSize: CGFloat = 12
    static let pillGap: CGFloat = 1
    static let roundedPillGap: CGFloat = 3
    static let minimumPillWidth: CGFloat = 44
    /// Equal-width tabs narrower than this drop their labels and show the icon only.
    static let equalCompactBelow: CGFloat = 96
    static let iconSize: CGFloat = 14
}

struct FreeStrip {
    enum Anchor: String {
        /// Middle of the bar (screens without a notch).
        case center
        /// Right end, against the notch.
        case trailing
        /// Left end (the user chose left alignment).
        case leading
    }

    /// Cocoa coordinates, pinned to the top edge of the screen with the menu bar's height plus the
    /// top overscan. This is the most the strip may cover.
    let frame: NSRect
    /// Where a narrower panel sits inside `frame`.
    let anchor: Anchor
    /// Short note for `--list` about how the region was found.
    let leftSource: String


    /// The panel frame for tabs that need `contentWidth`. Automatic width trims the region to the
    /// tabs at its anchor; fixed width uses the whole region.
    func panelFrame(contentWidth: CGFloat, mode: StripWidthMode) -> NSRect {
        guard mode == .automatic else { return frame }
        let width = min(frame.width, max(contentWidth, 1)).rounded(.up)
        var rect = frame
        rect.size.width = width
        switch anchor {
        case .center: rect.origin.x = (frame.midX - width / 2).rounded()
        case .trailing: rect.origin.x = frame.maxX - width
        case .leading: rect.origin.x = frame.minX
        }
        return rect
    }
}

enum MenuBarGeometry {
    /// Menu bar height actually reserved by the system on this screen (0 when auto-hidden).
    static func reservedMenuBarHeight(_ screen: NSScreen) -> CGFloat {
        max(0, screen.frame.maxY - screen.visibleFrame.maxY)
    }

    /// Strip height: the reserved menu bar height, or the status bar thickness as a fallback.
    static func menuBarHeight(_ screen: NSScreen) -> CGFloat {
        let reserved = reservedMenuBarHeight(screen)
        if reserved > 0 { return reserved }
        return externalBarHeights[NSStringFromRect(screen.frame)] ?? NSStatusBar.system.thickness
    }

    /// Menu bar heights measured from Accessibility on screens that report no reserved height.
    nonisolated(unsafe) static var externalBarHeights: [String: CGFloat] = [:]

    /// Top edge of the primary screen in Cocoa coordinates. The primary screen is the one at index 0.
    static func primaryMaxY() -> CGFloat {
        (NSScreen.screens.first ?? NSScreen.main)?.frame.maxY ?? 0
    }

    /// Converts a top-left-origin global rect (AX, CGWindowList) to Cocoa bottom-left coordinates.
    static func cocoaRect(fromTopLeft rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: primaryMaxY() - rect.maxY, width: rect.width, height: rect.height)
    }

    /// True when the frontmost app's focused window is full screen. Its menu bar is hidden then.
    static func frontmostIsFullScreen() -> Bool {
        guard AXIsProcessTrusted(),
              let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else {
            return false
        }
        let app = AXUIElementCreateApplication(pid)
        AX.setTimeout(app)
        // A helper window (a Find bar, a popover) can hold focus over a full-screen window, so the
        // app's main window counts too.
        return ["AXFocusedWindow", "AXMainWindow"].contains { attribute in
            AX.element(app, attribute).flatMap { AX.copy($0, "AXFullScreen") as? Bool } ?? false
        }
    }

    /// Largest right edge (Cocoa x) of the frontmost app's menu titles that sit on this screen's menu bar.
    static func frontmostMenuTitlesMaxX(on screen: NSScreen) -> CGFloat? {
        guard AXIsProcessTrusted(),
              let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else {
            return nil
        }
        let app = AXUIElementCreateApplication(pid)
        AX.setTimeout(app)
        guard let bar = AX.element(app, "AXMenuBar") else { return nil }

        // AX reports the menu titles for one display only (the one that is currently showing them).
        // Every display draws the same titles at the same offset from its own left edge, so measure
        // on that owner display and translate the result to the requested screen.
        var rects: [CGRect] = []
        for item in AX.elements(bar, "AXChildren") {
            guard let position = AX.point(item, "AXPosition"),
                  let size = AX.size(item, "AXSize") else {
                continue
            }
            rects.append(cocoaRect(fromTopLeft: CGRect(origin: position, size: size)))
        }
        guard let first = rects.first,
              let owner = NSScreen.screens.first(where: {
                  $0.frame.minX <= first.midX && first.midX <= $0.frame.maxX
                      && $0.frame.minY <= first.midY && first.midY <= $0.frame.maxY
              }) else {
            return nil
        }

        if reservedMenuBarHeight(owner) == 0,
           let barSize = AX.size(bar, "AXSize"),
           barSize.height > 0 {
            externalBarHeights[NSStringFromRect(owner.frame)] = barSize.height
        }

        let relativeMaxX = rects
            .filter { owner.frame.minX <= $0.midX && $0.midX <= owner.frame.maxX }
            .map { $0.maxX - owner.frame.minX }
            .max()
        return relativeMaxX.map { screen.frame.minX + $0 }
    }

    /// Left edge (Cocoa x) of the leftmost status item on this screen's menu bar, or nil if none.
    /// Status items are windows at the status-bar window level (25) inside the menu bar band.
    static func statusItemsMinX(on screen: NSScreen) -> CGFloat? {
        let infos = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        let ownPid = Int(ProcessInfo.processInfo.processIdentifier)
        let topY = primaryMaxY() - screen.frame.maxY
        let band = menuBarHeight(screen) + 4
        var minX: CGFloat?
        for info in infos {
            guard (info[kCGWindowLayer as String] as? Int) == 25,
                  (info[kCGWindowOwnerPID as String] as? Int) != ownPid,
                  let dict = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: dict) else { continue }
            // Status items are small. A wide window at this level is an overlay, not an icon.
            guard rect.width <= StripLayout.maxStatusItemWidth,
                  rect.minY >= topY - 1, rect.minY < topY + band,
                  rect.midX >= screen.frame.midX - 40, rect.midX <= screen.frame.maxX else { continue }
            minX = min(minX ?? rect.minX, rect.minX)
        }
        return minX
    }

    /// The strip region for one screen, or nil when it should be hidden.
    /// - Parameters:
    ///   - width: the strip width setting (the maximum in Automatic width mode).
    ///   - alignment: left alignment anchors a narrower panel to the region's left edge.
    ///   - hideInFullScreen: hide while the frontmost window is full screen.
    static func freeStrip(
        on screen: NSScreen,
        width: CGFloat = StripLayout.stripWidth,
        alignment: StripAlignment = .center,
        placement: StripPlacement = .middle,
        hideInFullScreen: Bool = true
    ) -> FreeStrip? {
        if hideInFullScreen, frontmostIsFullScreen() { return nil }

        // NSScreen.visibleFrame can report no reserved menu bar on an external display that does
        // have one, so reserved height alone is not enough. A screen counts as having a menu bar when
        // the system reserves one or the frontmost app's menu titles sit on it.
        let axMaxX = frontmostMenuTitlesMaxX(on: screen)
        guard reservedMenuBarHeight(screen) > 0 || axMaxX != nil else { return nil }

        // The strip is anchored to the middle of the bar, so it stays put whatever menus the
        // frontmost app has.
        // On a notched screen the middle is the notch, so the strip ends at the notch's left edge.
        var hi: CGFloat
        var lo: CGFloat
        var anchor: FreeStrip.Anchor = .center
        if let aux = screen.auxiliaryTopLeftArea {
            anchor = .trailing
            hi = aux.maxX - StripLayout.notchGap
            lo = hi - width
        } else {
            lo = screen.frame.midX - width / 2
            hi = lo + width
        }
        // Never overlap the right-hand status icons: when they reach into the strip, pull the right
        // edge back and slide left to keep the width.
        // On a notched screen the strip lives left of the notch and the status icons sit right of it.
        if screen.auxiliaryTopLeftArea == nil, let statusMinX = statusItemsMinX(on: screen) {
            hi = min(hi, statusMinX - StripLayout.statusGap)
        }
        // The frontmost app's menu titles are ignored on purpose: the strip may sit on top of them.
        // Right-click a tab and choose "Hide for ..." to reach the menus underneath. Only the Apple
        // menu and the app name are kept clear.
        if placement == .left {
            // Top left: start right after the Apple menu and end at the notch (or after `width`).
            lo = screen.frame.minX + StripLayout.leftPlacementInset
            hi = min(lo + width, screen.auxiliaryTopLeftArea.map { $0.maxX - StripLayout.notchGap } ?? .greatestFiniteMagnitude)
            if screen.auxiliaryTopLeftArea == nil, let statusMinX = statusItemsMinX(on: screen) {
                hi = min(hi, statusMinX - StripLayout.statusGap)
            }
            anchor = .leading
        } else {
            lo = max(screen.frame.minX + StripLayout.minimumLeftInset, min(lo, hi - width))
        }
        guard hi - lo >= StripLayout.minimumStripWidth else { return nil }

        // Tabs are a share of the bar height, flush with the top. The panel is only as tall as the
        // tabs (plus the overscan above the screen), so the rest of the bar stays clickable.
        let height = (menuBarHeight(screen) * CGFloat(Settings.shared.tabHeightPercent) / 100).rounded()
        let frame = NSRect(
            x: lo,
            y: screen.frame.maxY - height,
            width: hi - lo,
            height: height + StripLayout.topOverscan
        )
        if alignment == .left { anchor = .leading }
        return FreeStrip(
            frame: frame,
            anchor: anchor,
            leftSource: "menus ignored, anchor \(anchor.rawValue)"
        )
    }
}
