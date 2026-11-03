# Homebrew cask for Hark. Lives in the debanjanc01/homebrew-tap repository as Casks/hark.rb;
# for each release, update `version` and `sha256` (from the release's Hark-x.y.z.zip.sha256).
cask "hark" do
  version "0.2.7"
  sha256 "53b55e53ba4b1f3ddb76ab8fb67fdd0066d813fcd7f253ccc763b9269abb4f0d"

  url "https://github.com/debanjanc01/hark/releases/download/v#{version}/Hark-#{version}.zip"
  name "Hark"
  desc "Hold-to-talk dictation that runs entirely on your Mac"
  homepage "https://github.com/debanjanc01/hark"

  depends_on arch: :arm64
  depends_on macos: ">= :ventura"

  app "Hark.app"

  # Launch at Login is a LaunchAgent that Hark writes; remove it with the app.
  uninstall quit:      "io.github.debanjanc01.hark",
            launchctl: "io.github.debanjanc01.hark"

  zap trash: "~/Library/Preferences/io.github.debanjanc01.hark.plist"

  caveats <<~EOS
    Hark isn't notarized by Apple yet, so macOS blocks its first launch. Open it, then go to
    System Settings → Privacy & Security and click Open Anyway. You only need to do this once.
  EOS
end
