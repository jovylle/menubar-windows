// MenuBarGeometry.swift
// Computes the free strip inside the menu bar for one screen: the space between the frontmost app's
// menu titles (left) and the status icons (right).
//
// Gotchas:
// - Coordinate spaces: Cocoa (NSScreen, NSPanel) is bottom-left origin, measured from the primary
//   screen. AX and CGWindowList are top-left origin on the same global plane. Convert with
//   cocoaRect(fromTopLeft:): cocoaY = primaryScreen.frame.maxY - topLeftMaxY.
// - The menu bar is only reserved on the screen that shows it. A screen with zero reserved height
//   (menu bar auto-hidden, or no menu bar there) gets no strip.
// - AX menu items that do not lie on this screen's menu bar are ignored. If no items match, a fixed
//   offset from the left edge is used instead.
// - The strip is anchored to the middle of the bar (StripLayout.stripWidth wide), or ends at the notch
//   on notched screens. The frontmost app's menus only push its left edge in when they reach it.

import AppKit
import ApplicationServices

enum StripLayout {
    /// Width of the strip, centered on the screen (or ending at the notch on notched screens).
    static let stripWidth: CGFloat = 560
    /// Gap between the notch and the strip's right edge.
    static let notchGap: CGFloat = 12
    /// Gap between the last frontmost-app menu title and the strip.
    static let leftPadding: CGFloat = 12
    /// Left edge used when Accessibility cannot report the menu titles.
    static let fallbackLeftOffset: CGFloat = 420
    /// Below this width the strip is hidden.
    static let minimumStripWidth: CGFloat = 120
    static let pillHeight: CGFloat = 22
    static let pillFontSize: CGFloat = 12
    static let pillGap: CGFloat = 4
    static let minimumPillWidth: CGFloat = 44
    static let iconSize: CGFloat = 14
}

struct FreeStrip {
    /// Cocoa coordinates, pinned to the top edge of the screen with the menu bar's height.
    let frame: NSRect
    /// "AX" when the left edge came from the frontmost app's menu titles, "fallback" otherwise.
    let leftSource: String
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
        guard let window = AX.element(app, "AXFocusedWindow") else { return false }
        return (AX.copy(window, "AXFullScreen") as? Bool) ?? false
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

        if let barPos = AX.point(bar, "AXPosition"), let barSize = AX.size(bar, "AXSize"),
           barSize.height > 0, reservedMenuBarHeight(screen) == 0 {
            let r = cocoaRect(fromTopLeft: CGRect(origin: barPos, size: barSize))
            if r.midX >= screen.frame.minX, r.midX <= screen.frame.maxX, r.midY >= screen.frame.midY {
                externalBarHeights[NSStringFromRect(screen.frame)] = barSize.height
            }
        }
        let bandBottom = screen.frame.maxY - menuBarHeight(screen)
        var maxX: CGFloat?
        for item in AX.elements(bar, "AXChildren") {
            guard let position = AX.point(item, "AXPosition"),
                  let size = AX.size(item, "AXSize") else {
                continue
            }
            let rect = cocoaRect(fromTopLeft: CGRect(origin: position, size: size))
            // Keep only items inside this screen's menu bar band and horizontal range.
            guard rect.midY >= bandBottom,
                  rect.midX >= screen.frame.minX,
                  rect.midX <= screen.frame.maxX else {
                continue
            }
            maxX = max(maxX ?? rect.maxX, rect.maxX)
        }
        return maxX
    }

    /// The free strip for one screen, or nil when it should be hidden.
    static func freeStrip(on screen: NSScreen) -> FreeStrip? {
        guard !frontmostIsFullScreen() else { return nil }

        // NSScreen.visibleFrame can report no reserved menu bar on an external display that does
        // have one, so reserved height alone is not enough. A screen counts as having a menu bar when
        // the system reserves one or the frontmost app's menu titles sit on it.
        let axMaxX = frontmostMenuTitlesMaxX(on: screen)
        guard reservedMenuBarHeight(screen) > 0 || axMaxX != nil else { return nil }

        let left: CGFloat
        let source: String
        if let maxX = axMaxX {
            left = maxX + StripLayout.leftPadding
            source = "AX"
        } else {
            left = screen.frame.minX + StripLayout.fallbackLeftOffset
            source = "fallback"
        }

        // The strip is anchored to the middle of the bar, so it stays put when the frontmost app has
        // more or fewer menus. Only an app whose menus reach into the strip pushes its left edge in.
        // On a notched screen the middle is the notch, so the strip ends at the notch's left edge.
        let width = StripLayout.stripWidth
        var hi: CGFloat
        var lo: CGFloat
        if let aux = screen.auxiliaryTopLeftArea {
            hi = aux.maxX - StripLayout.notchGap
            lo = hi - width
        } else {
            lo = screen.frame.midX - width / 2
            hi = lo + width
        }
        lo = max(lo, left)
        guard hi - lo >= StripLayout.minimumStripWidth else { return nil }

        let height = menuBarHeight(screen)
        let frame = NSRect(x: lo, y: screen.frame.maxY - height, width: hi - lo, height: height)
        return FreeStrip(frame: frame, leftSource: source)
    }
}
