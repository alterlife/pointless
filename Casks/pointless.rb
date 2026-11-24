cask "pointless" do
  version "0.1.0"
  sha256 "e04b3831f69632e54036ce4ae7a659f959f5b8361fc5e6fe33badbfaa14df2eb"

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
