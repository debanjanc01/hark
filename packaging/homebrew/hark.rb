# Homebrew cask for Hark. Lives in the debanjanc01/homebrew-tap repository as Casks/hark.rb;
# for each release, update `version` and `sha256` (from the release's Hark-x.y.z.zip.sha256).
cask "hark" do
  version "0.2.10"
  sha256 "6dfb7763fc354d17c28badc9f76e0ded47f8a1b98bfd11d1aefc3dd68130dc67"

  url "https://github.com/debanjanc01/hark/releases/download/v#{version}/Hark-#{version}.zip"
  name "Hark"
  desc "Hold-to-talk dictation that runs entirely on your Mac"
  homepage "https://github.com/debanjanc01/hark"

  depends_on arch: :arm64
  depends_on macos: :ventura

  app "Hark.app"

  uninstall quit: "io.github.debanjanc01.hark"

  # Launch at Login is a LaunchAgent that Hark writes. Only zap removes it: `uninstall`
  # also runs on every upgrade, which would turn Launch at Login off.
  zap launchctl: "io.github.debanjanc01.hark",
      trash:     "~/Library/Preferences/io.github.debanjanc01.hark.plist"

  caveats <<~EOS
    Hark isn't notarized by Apple yet, so macOS blocks its first launch. Open it, then go to
    System Settings → Privacy & Security and click Open Anyway. You only need to do this once.
  EOS
end
