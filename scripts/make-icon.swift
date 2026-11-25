// make-icon.swift
// Draws the app icon with AppKit at every size macOS needs and writes an .iconset folder.
// Usage: swift scripts/make-icon.swift <output.iconset>
// scripts/make-icon.sh runs this, then iconutil, and puts the result in Resources/.
//
// The design, on a 1024 x 1024 canvas (bottom-left origin): a dark rounded square; a menu bar band
// across the top with a notch cutout in the middle; three square tabs hanging from the top edge left
// of the notch, the middle one active (brighter, with an accent underline); status dots right of the
// notch; and one window below whose title bar shares the active tab's accent. No text.

import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    FileHandle.standardError.write("usage: swift make-icon.swift <output.iconset>\n".data(using: .utf8)!)
    exit(2)
}
let output = URL(fileURLWithPath: arguments[1])
try? FileManager.default.removeItem(at: output)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xff) / 255,
        green: CGFloat((hex >> 8) & 0xff) / 255,
        blue: CGFloat(hex & 0xff) / 255,
        alpha: alpha
    )
}

let accent = color(0xF2A03D)

func drawIcon() {
    let body = NSRect(x: 100, y: 100, width: 824, height: 824)
    let bodyPath = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)

    // Soft drop shadow under the body.
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = 28
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.set()
    color(0x1B1E25).setFill()
    bodyPath.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    bodyPath.addClip()
    NSGradient(starting: color(0x2B303B), ending: color(0x171A20))?.draw(in: body, angle: -90)

    // Menu bar band.
    let bandHeight: CGFloat = 150
    let band = NSRect(x: body.minX, y: body.maxY - bandHeight, width: body.width, height: bandHeight)
    color(0x3B4250).setFill()
    band.fill()
    color(0x000000, 0.35).setFill()
    NSRect(x: band.minX, y: band.minY - 3, width: band.width, height: 3).fill()

    // Notch cutout, centered, with rounded bottom corners.
    let notch = NSRect(x: 432, y: band.maxY - 104, width: 160, height: 104 + 40)
    NSColor.black.setFill()
    NSBezierPath(roundedRect: notch, xRadius: 34, yRadius: 34).fill()

    // Three square tabs, flush with the top edge, ending left of the notch.
    let tabWidth: CGFloat = 74
    let gap: CGFloat = 6
    for index in 0..<3 {
        let x = 190 + CGFloat(index) * (tabWidth + gap)
        let tab = NSRect(x: x, y: band.minY, width: tabWidth, height: bandHeight)
        let active = index == 1
        color(0x0E1014, active ? 0.35 : 0.62).setFill()
        tab.fill()
        if active {
            NSColor.white.withAlphaComponent(0.16).setFill()
            tab.fill()
            accent.setFill()
            NSRect(x: tab.minX, y: tab.minY, width: tab.width, height: 12).fill()
        }
        // A small app-icon square inside each tab.
        let glyph = NSRect(x: tab.midX - 17, y: tab.midY - 11, width: 34, height: 34)
        (active ? NSColor.white : NSColor.white.withAlphaComponent(0.55)).setFill()
        NSBezierPath(roundedRect: glyph, xRadius: 9, yRadius: 9).fill()
    }

    // Status icons right of the notch.
    for (index, x) in [672.0, 728.0, 784.0].enumerated() {
        let dot = NSRect(x: x - 15, y: band.midY - 15, width: 30, height: 30)
        NSColor.white.withAlphaComponent(index == 2 ? 0.75 : 0.45).setFill()
        NSBezierPath(ovalIn: dot).fill()
    }

    // The window the active tab stands for.
    let window = NSRect(x: 196, y: 214, width: 632, height: 440)
    NSGraphicsContext.saveGraphicsState()
    let windowShadow = NSShadow()
    windowShadow.shadowColor = NSColor.black.withAlphaComponent(0.45)
    windowShadow.shadowBlurRadius = 24
    windowShadow.shadowOffset = NSSize(width: 0, height: -10)
    windowShadow.set()
    color(0xE9E6DF).setFill()
    NSBezierPath(roundedRect: window, xRadius: 36, yRadius: 36).fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: window, xRadius: 36, yRadius: 36).addClip()
    accent.setFill()
    NSRect(x: window.minX, y: window.maxY - 74, width: window.width, height: 74).fill()
    for (index, x) in [244.0, 290.0, 336.0].enumerated() {
        let light = NSRect(x: x - 13, y: window.maxY - 50, width: 26, height: 26)
        NSColor.white.withAlphaComponent(index == 0 ? 0.95 : 0.6).setFill()
        NSBezierPath(ovalIn: light).fill()
    }
    // Content lines.
    for (index, width) in [420.0, 520.0, 360.0, 470.0].enumerated() {
        let line = NSRect(x: window.minX + 52, y: window.maxY - 140 - CGFloat(index) * 66, width: width, height: 26)
        color(0x2B303B, 0.22).setFill()
        NSBezierPath(roundedRect: line, xRadius: 13, yRadius: 13).fill()
    }
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.restoreGraphicsState()

    // Thin inner highlight on the body edge.
    NSColor.white.withAlphaComponent(0.08).setStroke()
    let edge = NSBezierPath(roundedRect: body.insetBy(dx: 2, dy: 2), xRadius: 183, yRadius: 183)
    edge.lineWidth = 4
    edge.stroke()
}

func render(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    let scale = CGFloat(pixels) / 1024
    let transform = NSAffineTransform()
    transform.scale(by: scale)
    transform.concat()
    drawIcon()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let sizes: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024)
]
for (name, pixels) in sizes {
    try render(pixels: pixels).write(to: output.appendingPathComponent("\(name).png"))
}
print("wrote \(sizes.count) images to \(output.path)")
