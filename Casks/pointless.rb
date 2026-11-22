cask "pointless" do
  version "0.1.0"
  sha256 :no_check

  url "https://github.com/alterlife/pointless/releases/download/v#{version}/Pointless.dmg"
  name "Pointless"
  desc "Cursor-free keyboard navigation for macOS"
  homepage "https://github.com/alterlife/pointless"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :sequoia

  app "Pointless.app"

  zap trash: [
    "~/Library/Application Support/Pointless",
    "~/Library/Preferences/com.alterlife.pointless.plist",
  ]
end
