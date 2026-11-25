// DemoMode.swift
// Demo mode for screenshots and videos: `-mw.demo YES` replaces the real windows with invented ones
// (DemoData in MenubarWindowsCore) and generated icons, so a capture never shows the user's apps.
// Launch-only debug keys, not shown in Settings:
//   -mw.demo YES               fake windows, fake displays, fake pinned app names, permission shown as granted
//   -mw.demoCount <1...8>      number of fake windows (default 6)
//   -mw.demoActive <index>     which fake tab is focused (0-based, default 1)
//   -mw.demoMenu <index>       pop up the right-click menu of that tab about a second after launch
//   -mw.demoBackdrop YES       a plain dark blue backdrop window behind the strip (owned by this app)
//   -mw.openSettings YES       open Settings at launch (works without demo mode too)
//   -mw.settingsPane <name>    appearance, tabs, displays, behaviour, general or about
//   -mw.showOnboarding YES     open the first-run guide at launch (works without demo mode too)
//
// Gotchas:
// - Demo mode reads and writes its settings in a separate defaults suite that is wiped at every demo
//   launch, so a demo run never changes the user's real settings and real pinned apps never show.
//   A suite does not search the argument domain, so the `mw.` launch arguments are copied into it.
// - Clicking a fake tab only moves the active marker. Close, minimize and middle-click do nothing, and
//   no AX or CGWindowList call is made for fake windows.
// - All fake windows go to the first screen's strip; other screens show no strip in demo mode.

import AppKit
import MenubarWindowsCore

enum DemoMode {
    private static let arguments = UserDefaults.standard

    static let isOn = arguments.bool(forKey: "mw.demo")

    /// Settings store for demo runs: a throwaway suite, emptied at launch. A suite does not see the
    /// launch arguments, so the `mw.` ones are copied in.
    static let store: UserDefaults = {
        let name = "\(AppInfo.displayName).demo"
        guard let store = UserDefaults(suiteName: name) else { return .standard }
        store.removePersistentDomain(forName: name)
        let launchArguments = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        for (key, value) in launchArguments where key.hasPrefix("mw.") {
            store.set(value, forKey: key)
        }
        return store
    }()

    static let count = DemoData.clampedCount(integer("mw.demoCount"))

    static let snapshots = DemoData.windows(count: count)

    /// The focused fake window. Clicking a fake tab moves it.
    private(set) static var activeID: UInt32? = DemoData.windowID(
        at: DemoData.clampedActiveIndex(integer("mw.demoActive"), count: count),
        in: snapshots
    )

    static var menuTabIndex: Int? { integer("mw.demoMenu") }
    static var showsBackdrop: Bool { arguments.bool(forKey: "mw.demoBackdrop") }

    static var openSettingsAtLaunch: Bool { arguments.bool(forKey: "mw.openSettings") }
    static var showOnboardingAtLaunch: Bool { arguments.bool(forKey: "mw.showOnboarding") }

    private static func integer(_ key: String) -> Int? {
        arguments.object(forKey: key) == nil ? nil : arguments.integer(forKey: key)
    }

    static func activate(_ windowID: CGWindowID) {
        activeID = windowID
    }

    /// The fake windows as tab sources, with the active one marked focused.
    static var windows: [WindowInfo] {
        snapshots.map { snapshot in
            WindowInfo(
                windowID: snapshot.windowID, pid: snapshot.pid, appKey: snapshot.appKey,
                appName: snapshot.appName, title: snapshot.title, frame: snapshot.frame,
                isFocused: snapshot.windowID == activeID, isMinimized: false
            )
        }
    }

    // MARK: Unbundled builds

    /// The source checkout a bare `.build/<config>/MenubarWindows` binary was built in, found by walking up
    /// from the executable to the folder that holds VERSION. Demo mode only.
    private static let sourceRoot: URL? = {
        guard isOn, !AppInfo.isBundled else { return nil }
        var folder = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().deletingLastPathComponent()
        for _ in 0..<4 {
            if FileManager.default.fileExists(atPath: folder.appendingPathComponent("VERSION").path) { return folder }
            folder.deleteLastPathComponent()
        }
        return nil
    }()

    /// VERSION from the source checkout, so an unbundled demo build shows the real version, not "dev".
    static var sourceVersion: String? {
        sourceRoot.flatMap { try? String(contentsOf: $0.appendingPathComponent("VERSION"), encoding: .utf8) }?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// An unbundled binary has no app icon, so About would show a generic one. Use the committed icon.
    static func applyAppIcon() {
        guard let url = sourceRoot?.appendingPathComponent("Resources/AppIcon-1024.png"),
              let image = NSImage(contentsOf: url) else { return }
        NSApp.applicationIconImage = image
    }

    // MARK: Icons

    private static var iconCache: [String: NSImage] = [:]

    /// A rounded square in the app's color with its letter, drawn in code at any resolution.
    static func icon(appKey: String, size: CGFloat = StripLayout.iconSize) -> NSImage? {
        guard let app = DemoData.app(forKey: appKey) else { return nil }
        let cacheKey = "\(appKey)@\(size)"
        if let cached = iconCache[cacheKey] { return cached }
        let color = NSColor(srgbRed: app.red, green: app.green, blue: app.blue, alpha: 1)
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let square = rect.insetBy(dx: rect.width * 0.04, dy: rect.height * 0.04)
            let path = NSBezierPath(roundedRect: square, xRadius: square.width * 0.24, yRadius: square.height * 0.24)
            NSGradient(starting: color.blended(withFraction: 0.18, of: .white) ?? color, ending: color)?
                .draw(in: path, angle: -90)
            let font = NSFont.systemFont(ofSize: square.height * 0.62, weight: .bold)
            let text = NSAttributedString(string: app.letter, attributes: [.font: font, .foregroundColor: NSColor.white])
            let textSize = text.size()
            text.draw(at: NSPoint(x: square.midX - textSize.width / 2, y: square.midY - textSize.height / 2))
            return true
        }
        iconCache[cacheKey] = image
        return image
    }

    // MARK: Settings data

    /// Name for a pinned app key in demo mode.
    static func appName(forKey key: String) -> String {
        DemoData.app(forKey: key)?.name ?? "Demo app"
    }
}

/// A plain dark blue gradient window that sits right behind the strip in demo mode, so a capture of
/// the translucent strip shows this backdrop instead of the real menu bar. It ignores the mouse.
final class DemoBackdrop {
    private let window: NSWindow
    static let margin: CGFloat = 80

    init() {
        window = NSWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        window.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue - 1)
        window.isOpaque = true
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.contentView = GradientView()
        window.title = "Demo backdrop"
    }

    /// Covers the strip panel's frame plus a margin, clipped to the top of its screen.
    func follow(_ stripFrame: NSRect) {
        let frame = stripFrame.insetBy(dx: -Self.margin, dy: -Self.margin)
        if window.frame != frame { window.setFrame(frame, display: true) }
        if !window.isVisible { window.orderFrontRegardless() }
    }

    private final class GradientView: NSView {
        override func draw(_ dirtyRect: NSRect) {
            NSGradient(
                starting: NSColor(srgbRed: 0.10, green: 0.16, blue: 0.34, alpha: 1),
                ending: NSColor(srgbRed: 0.04, green: 0.07, blue: 0.18, alpha: 1)
            )?.draw(in: bounds, angle: -90)
        }
    }
}
