// screenshot-tool.swift
// Helper for scripts/capture-screenshots.sh. Built with swiftc into .build/, no dependencies.
//   windows <pid>                               list on-screen windows of that process only:
//                                               id layer x y width height (points, top-left origin) name
//   crop <in.png> <out.png> <x> <y> <w> <h>     crop a rectangle given in pixels from the top-left
//   trim <in.png> <out.png>                     drop fully transparent rows and columns at the edges
//   pixel <in.png> <x> <y>                      print the red, green and blue values (0-255) of a pixel
//   hero <strip.png> <menu.png> <out.png> <light|black> <menuOffsetPt> <tabHeightPt>
//                                               compose a 1920x1080 image: gradient, drawn menu bar,
//                                               the real strip capture in the middle of the bar and the
//                                               real menu capture hanging below the strip
//   notch <strip.png> <out.png> <light|black> <tabHeightPt>
//                                               compose a 1800x260 image of the top-left corner of a notched
//                                               MacBook: bezel, rounded screen corner, drawn menu bar with the
//                                               notch, and the real strip capture between the Apple menu and
//                                               the notch (the layout of a 14-inch MacBook Pro, 1512pt wide)
//
// Gotchas:
// - `windows` filters by process ID, never by owner name alone: another copy of the app may be running
//   with the user's real windows, and its windows must never be captured.
// - Captures are 2x (retina). The hero is drawn at 1.5 px per point, so captures are scaled by 0.75.
// - PNGs are written with CoreGraphics and carry no text metadata.

import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

func fail(_ message: String) -> Never {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    exit(1)
}

func load(_ path: String) -> CGImage {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { fail("cannot read \(path)") }
    return image
}

func save(_ image: CGImage, _ path: String) {
    guard let destination = CGImageDestinationCreateWithURL(
        URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil
    ) else { fail("cannot write \(path)") }
    CGImageDestinationAddImage(destination, image, nil)
    if !CGImageDestinationFinalize(destination) { fail("cannot write \(path)") }
}

func context(width: Int, height: Int, opaque: Bool = false) -> CGContext {
    guard let ctx = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: (opaque ? CGImageAlphaInfo.noneSkipLast : CGImageAlphaInfo.premultipliedLast).rawValue
    ) else { fail("cannot create a bitmap") }
    return ctx
}

func listWindows(pid: Int) {
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    for window in list where (window[kCGWindowOwnerPID as String] as? Int) == pid {
        let bounds = window[kCGWindowBounds as String] as? [String: Any] ?? [:]
        func number(_ key: String) -> Int { Int((bounds[key] as? Double) ?? 0) }
        let id = window[kCGWindowNumber as String] as? Int ?? 0
        let layer = window[kCGWindowLayer as String] as? Int ?? 0
        let name = (window[kCGWindowName as String] as? String) ?? ""
        print("\(id) \(layer) \(number("X")) \(number("Y")) \(number("Width")) \(number("Height")) \(name)")
    }
}

func crop(_ input: String, _ output: String, _ rect: CGRect) {
    guard let cropped = load(input).cropping(to: rect) else { fail("crop is outside the image") }
    save(cropped, output)
}

/// Removes fully transparent rows and columns around the content.
func trim(_ input: String, _ output: String) {
    let image = load(input)
    let width = image.width, height = image.height
    let ctx = context(width: width, height: height)
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    guard let data = ctx.data?.assumingMemoryBound(to: UInt8.self) else { fail("no pixels") }
    let stride = ctx.bytesPerRow
    var minX = width, minY = height, maxX = -1, maxY = -1
    for y in 0..<height {
        for x in 0..<width where data[y * stride + x * 4 + 3] > 8 {
            minX = min(minX, x); maxX = max(maxX, x)
            minY = min(minY, y); maxY = max(maxY, y)
        }
    }
    guard maxX >= minX, maxY >= minY else { fail("image is empty") }
    // The bitmap rows run top to bottom in memory, which matches CGImage cropping coordinates.
    crop(input, output, CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1))
}

func hero(strip: String, menu: String, output: String, black: Bool, menuOffset: CGFloat, tabHeight: CGFloat) {
    let width = 1920, height = 1080
    let scale: CGFloat = 1.5          // px per point in the hero
    let captureScale: CGFloat = 2     // px per point in the captures
    let fit = scale / captureScale
    let ctx = context(width: width, height: height, opaque: true)
    let size = CGSize(width: width, height: height)

    // Backdrop: a plain vertical gradient, no text. Vertical keeps the PNG small (rows repeat).
    let colors: [CGColor] = black
        ? [CGColor(srgbRed: 0.09, green: 0.13, blue: 0.30, alpha: 1), CGColor(srgbRed: 0.02, green: 0.04, blue: 0.12, alpha: 1)]
        : [CGColor(srgbRed: 0.62, green: 0.74, blue: 0.95, alpha: 1), CGColor(srgbRed: 0.84, green: 0.80, blue: 0.96, alpha: 1)]
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size.height), end: CGPoint(x: 0, y: 0), options: [])

    // Menu bar: a translucent band at the top. The bar is taller than the tabs (tabs are 85% of it).
    let barHeight = (tabHeight / 0.85 * scale).rounded()
    let barRect = CGRect(x: 0, y: size.height - barHeight, width: size.width, height: barHeight)
    ctx.setFillColor(black ? CGColor(gray: 0, alpha: 0.45) : CGColor(gray: 1, alpha: 0.55))
    ctx.fill(barRect)

    let graphics = NSGraphicsContext(cgContext: ctx, flipped: false)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphics
    let textColor: NSColor = black ? .white : NSColor(white: 0.08, alpha: 1)
    let fontSize = 13 * scale
    let baseline = barRect.midY - fontSize * 0.36
    var x: CGFloat = 20 * scale
    if let apple = NSImage(systemSymbolName: "apple.logo", accessibilityDescription: nil)?
        .withSymbolConfiguration(.init(pointSize: fontSize * 1.05, weight: .regular)) {
        let tinted = NSImage(size: apple.size, flipped: false) { rect in
            apple.draw(in: rect)
            textColor.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        tinted.draw(in: CGRect(x: x, y: barRect.midY - apple.size.height / 2, width: apple.size.width, height: apple.size.height))
        x += apple.size.width + 18 * scale
    }
    for (index, title) in ["Draftpad", "File", "Edit", "View", "Window", "Help"].enumerated() {
        let font = NSFont.systemFont(ofSize: fontSize, weight: index == 0 ? .bold : .regular)
        let text = NSAttributedString(string: title, attributes: [.font: font, .foregroundColor: textColor])
        text.draw(at: CGPoint(x: x, y: baseline))
        x += text.size().width + 20 * scale
    }
    let clock = NSAttributedString(string: "Tue 9:41", attributes: [
        .font: NSFont.systemFont(ofSize: fontSize, weight: .regular), .foregroundColor: textColor
    ])
    clock.draw(at: CGPoint(x: size.width - clock.size().width - 20 * scale, y: baseline))
    NSGraphicsContext.restoreGraphicsState()

    // The real strip capture, centered in the bar. Its top rows are the overscan above the screen edge,
    // so it is drawn with its tab bodies flush with the top of the bar.
    let stripImage = load(strip)
    let stripSize = CGSize(width: CGFloat(stripImage.width) * fit, height: CGFloat(stripImage.height) * fit)
    let stripOrigin = CGPoint(x: ((size.width - stripSize.width) / 2).rounded(), y: size.height - tabHeight * scale)
    let overscan = stripSize.height - tabHeight * scale
    let stripRect = CGRect(x: stripOrigin.x, y: stripOrigin.y, width: stripSize.width, height: stripSize.height - overscan)
    ctx.saveGState()
    ctx.clip(to: CGRect(x: 0, y: 0, width: size.width, height: size.height))
    ctx.interpolationQuality = .high
    ctx.draw(stripImage, in: CGRect(origin: stripRect.origin, size: stripSize))
    ctx.restoreGState()

    // The real context menu capture, hanging below the strip at the offset it opened at.
    let menuImage = load(menu)
    let menuSize = CGSize(width: CGFloat(menuImage.width) * fit, height: CGFloat(menuImage.height) * fit)
    let menuRect = CGRect(
        x: (stripRect.minX + menuOffset * scale).rounded(),
        y: barRect.minY - 4 * scale - menuSize.height,
        width: menuSize.width, height: menuSize.height
    )
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -6 * scale), blur: 24 * scale, color: CGColor(gray: 0, alpha: 0.35))
    ctx.interpolationQuality = .high
    ctx.draw(menuImage, in: menuRect)
    ctx.restoreGState()

    guard let image = ctx.makeImage() else { fail("cannot render") }
    save(image, output)
}

/// The top-left corner of a notched MacBook with the real strip between the Apple menu and the notch.
/// Geometry in points follows a 14-inch display: the notch spans x 663 to 848, the menu bar is 34pt high,
/// and the app's region starts 42pt from the left edge. Drawn at 2 px per point, like the captures.
func notchHero(strip: String, output: String, black: Bool, tabHeight: CGFloat) {
    let width = 1800, height = 260
    let px: CGFloat = 2
    let bezel: CGFloat = 24
    let ctx = context(width: width, height: height, opaque: true)
    let size = CGSize(width: width, height: height)

    ctx.setFillColor(CGColor(srgbRed: 0.07, green: 0.07, blue: 0.08, alpha: 1))
    ctx.fill(CGRect(origin: .zero, size: size))

    // The screen: its top-left corner is rounded, the other edges run off the image.
    let screen = CGRect(x: bezel, y: -40, width: size.width - bezel + 40, height: size.height - bezel + 40)
    let radius: CGFloat = 26
    let path = CGMutablePath()
    path.move(to: CGPoint(x: screen.minX, y: screen.minY))
    path.addLine(to: CGPoint(x: screen.minX, y: screen.maxY - radius))
    path.addArc(center: CGPoint(x: screen.minX + radius, y: screen.maxY - radius), radius: radius,
                startAngle: .pi, endAngle: .pi / 2, clockwise: true)
    path.addLine(to: CGPoint(x: screen.maxX, y: screen.maxY))
    path.addLine(to: CGPoint(x: screen.maxX, y: screen.minY))
    path.closeSubpath()
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()

    let colors: [CGColor] = black
        ? [CGColor(srgbRed: 0.09, green: 0.13, blue: 0.30, alpha: 1), CGColor(srgbRed: 0.02, green: 0.04, blue: 0.12, alpha: 1)]
        : [CGColor(srgbRed: 0.62, green: 0.74, blue: 0.95, alpha: 1), CGColor(srgbRed: 0.84, green: 0.80, blue: 0.96, alpha: 1)]
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size.height - bezel), end: CGPoint(x: 0, y: 0), options: [])

    let top = size.height - bezel            // y of the top edge of the screen
    let barHeight = 34 * px
    let barRect = CGRect(x: screen.minX, y: top - barHeight, width: screen.width, height: barHeight)
    ctx.setFillColor(black ? CGColor(gray: 0, alpha: 0.45) : CGColor(gray: 1, alpha: 0.55))
    ctx.fill(barRect)

    func pointX(_ points: CGFloat) -> CGFloat { screen.minX + points * px }

    let graphics = NSGraphicsContext(cgContext: ctx, flipped: false)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphics
    let textColor: NSColor = black ? .white : NSColor(white: 0.08, alpha: 1)
    let fontSize = 13 * px
    func symbol(_ name: String, at points: CGFloat, size pointSize: CGFloat) {
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: pointSize, weight: .regular)) else { return }
        let tinted = NSImage(size: image.size, flipped: false) { rect in
            image.draw(in: rect)
            textColor.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        tinted.draw(in: CGRect(x: pointX(points), y: barRect.midY - image.size.height / 2, width: image.size.width, height: image.size.height))
    }
    symbol("apple.logo", at: 14, size: fontSize * 1.05)
    symbol("wifi", at: 858, size: fontSize * 0.95)
    symbol("battery.100", at: 876, size: fontSize * 0.95)
    NSGraphicsContext.restoreGraphicsState()

    // The real strip capture, 2x, tab bodies flush with the top of the screen.
    let stripImage = load(strip)
    let stripSize = CGSize(width: CGFloat(stripImage.width), height: CGFloat(stripImage.height))
    ctx.interpolationQuality = .high
    ctx.draw(stripImage, in: CGRect(x: pointX(42), y: top - tabHeight * px, width: stripSize.width, height: stripSize.height))

    // The notch: black, square at the top, rounded at the bottom.
    let notchLeft = pointX(663), notchRight = pointX(848)
    let notchBottom = top - 33 * px
    let corner: CGFloat = 12 * px
    let notch = CGMutablePath()
    notch.move(to: CGPoint(x: notchLeft, y: top + 2))
    notch.addLine(to: CGPoint(x: notchLeft, y: notchBottom + corner))
    notch.addArc(center: CGPoint(x: notchLeft + corner, y: notchBottom + corner), radius: corner,
                 startAngle: .pi, endAngle: 3 * .pi / 2, clockwise: false)
    notch.addLine(to: CGPoint(x: notchRight - corner, y: notchBottom))
    notch.addArc(center: CGPoint(x: notchRight - corner, y: notchBottom + corner), radius: corner,
                 startAngle: 3 * .pi / 2, endAngle: 0, clockwise: false)
    notch.addLine(to: CGPoint(x: notchRight, y: top + 2))
    notch.closeSubpath()
    ctx.setFillColor(CGColor(gray: 0, alpha: 1))
    ctx.addPath(notch)
    ctx.fillPath()
    ctx.restoreGState()

    guard let image = ctx.makeImage() else { fail("cannot render") }
    save(image, output)
}

let args = CommandLine.arguments
guard args.count >= 2 else { fail("usage: screenshot-tool windows|crop|trim|hero ...") }
switch args[1] {
case "windows" where args.count == 3:
    listWindows(pid: Int(args[2]) ?? -1)
case "crop" where args.count == 8:
    let n = args[4...7].map { Double($0) ?? 0 }
    crop(args[2], args[3], CGRect(x: n[0], y: n[1], width: n[2], height: n[3]))
case "pixel" where args.count == 5:
    let image = load(args[2])
    let ctx = context(width: image.width, height: image.height)
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    guard let data = ctx.data?.assumingMemoryBound(to: UInt8.self),
          let x = Int(args[3]), let y = Int(args[4]), x < image.width, y < image.height else { fail("bad pixel") }
    let offset = y * ctx.bytesPerRow + x * 4
    print(data[offset], data[offset + 1], data[offset + 2])
case "trim" where args.count == 4:
    trim(args[2], args[3])
case "hero" where args.count == 8:
    hero(strip: args[2], menu: args[3], output: args[4], black: args[5] == "black",
         menuOffset: CGFloat(Double(args[6]) ?? 0), tabHeight: CGFloat(Double(args[7]) ?? 29))
case "notch" where args.count == 6:
    notchHero(strip: args[2], output: args[3], black: args[4] == "black", tabHeight: CGFloat(Double(args[5]) ?? 29))
default:
    fail("usage: screenshot-tool windows|crop|trim|hero|notch ...")
}
