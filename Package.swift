// swift-tools-version:5.9
// Swift 5 language mode on purpose: the Accessibility and CoreGraphics C APIs use global CFString
// constants that Swift 6 strict concurrency flags. No third-party dependencies.
import PackageDescription

let package = Package(
    name: "MenubarWindows",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "MenubarWindows",
            path: "Sources/MenubarWindows"
        )
    ]
)
