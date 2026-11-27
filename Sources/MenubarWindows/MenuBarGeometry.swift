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
// - On notched screens (auxiliaryTopLeftArea) the region is everything between the Apple menu
//   (appleMenuInset) and the notch. Elsewhere it is the configured strip width: Left starts right after
//   the Apple menu, and Middle and Right sit in the middle of the bar (minimumLeftInset keeps the Apple
//   menu and app name clear). The frontmost app's menus are ignored on purpose; "Hide for ..." reaches them.
// - "Cover the Apple menu" moves the left edge to the screen edge. It applies to the region's left edge on
//   a notched screen and to Left elsewhere. Middle and Right off a notch keep their place.
// - Alignment inside the region comes from StripPlacement (Core). Left hugs the leading edge on every
//   screen (on a notched screen the center option is the one titled Left). Middle centers off a notch;
//   Right, and Middle on a notch, hug the trailing edge. Three or more tabs fill the whole region.
// - Status icons are windows at level 25 (status bar) inside the bar band. The region's right edge is
//   pulled back to stay clear of them, sliding left to keep the width.
// - The panel extends topOverscan points ABOVE the screen's top edge, so a click with the pointer
//   pushed against the very top still lands on a tab.

import AppKit
import ApplicationServices
import MenubarWindowsCore

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
    /// Middle and Right never start closer than this to the left screen edge (keeps the Apple menu usable).
    static let minimumLeftInset: CGFloat = 130
    /// Left starts this far from the screen edge (on a notched or any other screen), which keeps the Apple
    /// menu clear. Cover the Apple menu starts it at the edge instead.
    static let appleMenuInset: CGFloat = 42
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
    /// Cocoa coordinates, pinned to the top edge of the screen with the menu bar's height plus the
    /// top overscan. This is the most the strip may cover.
    let frame: NSRect
    /// Which edge of `frame` a narrower panel sits against.
    let anchor: StripPlacement.Edge
    /// Short note for `--list` about how the region was found.
    let leftSource: String


    /// The panel frame for tabs that need `contentWidth`. Automatic width trims the region to the
    /// tabs at its anchor; fixed width, or `fills` (three or more tabs), uses the whole region.
    func panelFrame(contentWidth: CGFloat, mode: StripWidthMode, fills: Bool = false) -> NSRect {
        guard mode == .automatic, !fills else { return frame }
        let width = min(frame.width, max(contentWidth, 1)).rounded(.up)
        var rect = frame
        rect.size.width = width
        switch anchor {
        case .leading: rect.origin.x = frame.minX
        case .center: rect.origin.x = (frame.midX - width / 2).rounded()
        case .trailing: rect.origin.x = frame.maxX - width
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
    ///   - width: the strip width setting (the maximum in Automatic width mode). Ignored on a notched
    ///     screen, where the strip may use everything between the Apple menu and the notch.
    ///   - alignment: right anchors a narrower panel to the region's right edge; Left (the center option on a
    ///     notched screen) hugs the Apple menu side on any screen; Middle centers it off a notch. See StripPlacement.
    ///   - coverAppleMenu: start at the very left edge, over the Apple menu, so the pointer thrown into the
    ///     top left corner lands on the first tab. Applies to a notched screen and to Left.
    ///   - hideInFullScreen: hide while the frontmost window is full screen.
    static func freeStrip(
        on screen: NSScreen,
        width: CGFloat = StripLayout.stripWidth,
        alignment: StripAlignment = .center,
        coverAppleMenu: Bool = false,
        hideInFullScreen: Bool = true
    ) -> FreeStrip? {
        if hideInFullScreen, frontmostIsFullScreen() { return nil }

        // NSScreen.visibleFrame can report no reserved menu bar on an external display that does
        // have one, so reserved height alone is not enough. A screen counts as having a menu bar when
        // the system reserves one or the frontmost app's menu titles sit on it.
        let axMaxX = frontmostMenuTitlesMaxX(on: screen)
        guard reservedMenuBarHeight(screen) > 0 || axMaxX != nil else { return nil }

        // On a notched screen the territory is the whole bar between the Apple menu and the notch.
        // Elsewhere it is `width` wide: Left starts next to the Apple menu and only gives way to the status
        // icons on its right; Middle and Right are a block centered in the bar, clear of the status icons.
        let lo: CGFloat
        let hi: CGFloat
        if let aux = screen.auxiliaryTopLeftArea {
            lo = screen.frame.minX + (coverAppleMenu ? 0 : StripLayout.appleMenuInset)
            hi = aux.maxX - StripLayout.notchGap
        } else if alignment == .left {
            let span = StripPlacement.leftSpan(
                screenMinX: screen.frame.minX,
                width: width,
                appleMenuInset: StripLayout.appleMenuInset,
                coverAppleMenu: coverAppleMenu,
                statusMinX: statusItemsMinX(on: screen),
                statusGap: StripLayout.statusGap
            )
            lo = span.lo
            hi = span.hi
        } else {
            let minLo = screen.frame.minX + StripLayout.minimumLeftInset
            var centeredLo = max(minLo, screen.frame.midX - width / 2)
            var centeredHi = screen.frame.midX + width / 2
            // Never overlap the right-hand status icons: pull the right edge back and slide left to
            // keep the width.
            if let statusMinX = statusItemsMinX(on: screen) {
                centeredHi = min(centeredHi, statusMinX - StripLayout.statusGap)
                centeredLo = max(minLo, min(centeredLo, centeredHi - width))
            }
            lo = centeredLo
            hi = centeredHi
        }
        // The frontmost app's menu titles are ignored on purpose: the strip may sit on top of them.
        // Right-click a tab and choose "Hide for ..." to reach the menus underneath. Only the Apple
        // menu and the app name are kept clear.
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
        let anchor = StripPlacement.edge(
            rightChoice: alignment == .right,
            onNotchedScreen: screen.auxiliaryTopLeftArea != nil,
            leftChoice: alignment == .left
        )
        return FreeStrip(
            frame: frame,
            anchor: anchor,
            leftSource: "menus ignored, anchor \(anchor.rawValue)"
        )
    }
}
