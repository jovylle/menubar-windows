cask "menubarwindows" do
  version "0.1.0"
  sha256 "658512fa0bf17908381314f8b56297ddc9861a8cc5772f5b8f82f42c39db4f57"

  url "https://github.com/jovylle/menubar-windows/releases/download/v#{version}/MenubarWindows-#{version}.dmg"
  name "MenubarWindows"
  desc "Window tabs in the empty space of the macOS menu bar"
  homepage "https://github.com/jovylle/menubar-windows"

  livecheck do
    url :url
    strategy :github_latest
  end

  # The build is arm64 only and needs macOS 13 or newer.
  depends_on arch: :arm64
  depends_on macos: :ventura

  app "MenubarWindows.app"

  zap trash: [
    "~/Library/Preferences/com.jovylle.menubarwindows.plist",
    "~/Library/Saved Application State/com.jovylle.menubarwindows.savedState",
  ]

  caveats <<~EOS
    This build is not notarized by Apple yet, so macOS blocks the first launch.
    Open System Settings > Privacy & Security, scroll down and click "Open Anyway".

    MenubarWindows needs the Accessibility permission to list and raise windows:
    System Settings > Privacy & Security > Accessibility, then switch on MenubarWindows.
    macOS may ask for it again after an update, until the app is notarized.
  EOS
end
