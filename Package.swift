// swift-tools-version:5.9
// Swift 5 language mode on purpose: the Accessibility and CoreGraphics C APIs use global CFString
// constants that Swift 6 strict concurrency flags. No third-party dependencies.
//
// MenubarWindowsCore holds pure, UI-free logic (tab ordering, labels) so it can be unit tested with
// `swift test` (Swift Testing, which ships with the Command Line Tools). The app target links it.
import PackageDescription

let package = Package(
    name: "MenubarWindows",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "MenubarWindowsCore",
            path: "Sources/MenubarWindowsCore"
        ),
        .executableTarget(
            name: "MenubarWindows",
            dependencies: ["MenubarWindowsCore"],
            path: "Sources/MenubarWindows"
        ),
        .testTarget(
            name: "MenubarWindowsCoreTests",
            dependencies: ["MenubarWindowsCore"],
            path: "Tests/MenubarWindowsCoreTests"
        )
    ]
)
