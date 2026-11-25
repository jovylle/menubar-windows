cask "menubarwindows" do
  version "0.1.0"
  # scripts/release.sh rewrites this line from the built dmg.
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

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
  depends_on macos: ">= :ventura"

  app "MenubarWindows.app"

  zap trash: [
    "~/Library/Preferences/com.jovylle.menubarwindows.plist",
    "~/Library/Saved Application State/com.jovylle.menubarwindows.savedState",
  ]
end
