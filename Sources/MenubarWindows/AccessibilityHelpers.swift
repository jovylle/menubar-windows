// AccessibilityHelpers.swift
// Thin wrappers over the C Accessibility (AX) API. Attribute names are the string values of the
// kAX*Attribute constants (for example "AXWindows"), which avoids global CFString concurrency noise.
//
// Gotchas:
// - AX positions use a GLOBAL, TOP-LEFT origin (y grows downward from the top of the primary
//   display). Cocoa frames (NSScreen, NSWindow) use a BOTTOM-LEFT origin. Convert with
//   MenuBarGeometry.cocoaRect(fromTopLeft:) before comparing against screen frames.
// - _AXUIElementGetWindow is a private HIServices symbol that window managers have used for years.
//   It maps an AX window to its CGWindowID without Screen Recording permission. If it fails,
//   WindowProvider falls back to matching by bounds.
// - AX calls are synchronous IPC on the main thread. A hung app can stall us, so every app element
//   gets a short messaging timeout.

import AppKit
import ApplicationServices

@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError

enum AX {
    static func setTimeout(_ element: AXUIElement) {
        AXUIElementSetMessagingTimeout(element, 0.2)
    }

    static func copy(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        copy(element, attribute) as? String
    }

    static func elements(_ element: AXUIElement, _ attribute: String) -> [AXUIElement] {
        (copy(element, attribute) as? [AXUIElement]) ?? []
    }

    static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let value = copy(element, attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return (value as! AXUIElement)
    }

    static func point(_ element: AXUIElement, _ attribute: String) -> CGPoint? {
        guard let value = copy(element, attribute), CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        var point = CGPoint.zero
        return AXValueGetValue(value as! AXValue, .cgPoint, &point) ? point : nil
    }

    static func size(_ element: AXUIElement, _ attribute: String) -> CGSize? {
        guard let value = copy(element, attribute), CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        var size = CGSize.zero
        return AXValueGetValue(value as! AXValue, .cgSize, &size) ? size : nil
    }

    static func windowID(_ element: AXUIElement) -> CGWindowID? {
        var id = CGWindowID(0)
        guard _AXUIElementGetWindow(element, &id) == .success, id != 0 else {
            return nil
        }
        return id
    }
}
