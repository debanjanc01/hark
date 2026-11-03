# Homebrew formula for Hark. Lives in the debanjanc01/homebrew-tap repository as
# Formula/hark.rb; for each release, update `url`, `sha256` and the `bottle` block
# (the release workflow prints it). The release workflow also builds from this file.
class Hark < Formula
  desc "Hold-to-talk dictation for macOS that runs entirely on your Mac"
  homepage "https://github.com/debanjanc01/hark"
  url "https://github.com/debanjanc01/hark/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "REPLACE_WITH_RELEASE_TARBALL_SHA256"
  license "MIT"

  # Prebuilt Hark (see RELEASING.md). Macs it doesn't cover build from source.
  # bottle do
  #   root_url "https://github.com/debanjanc01/hark/releases/download/vX.Y.Z"
  #   sha256 cellar: :any_skip_relocation, arm64_sonoma: "…"
  # end

  depends_on arch: :arm64
  depends_on macos: :ventura

  # Pinned and checksummed, matching scripts/fetch-deps.sh.
  resource "libneedle" do
    url "https://huggingface.co/Cactus-Compute/needle3/resolve/d6c7d6a2e9655505e0f8e23339356dd1705900eb/macos-arm64/libneedle.a"
    sha256 "7d1368a4a42a745aba055f310913c3ed6d929dee98a89dcb955b9032b2335700"
  end

  resource "whistle" do
    url "https://huggingface.co/Cactus-Compute/whistle/resolve/741118687e1f008f06d1351a402a731274789790/whistle.cact"
    sha256 "b6e02f048568ac5d01a2042556c658061e699acbc0aa2a1439f52f3d461dffeb"
  end

  def install
    resource("libneedle").stage { (buildpath/"vendor/needle").install "libneedle.a" }
    resource("whistle").stage { (buildpath/"vendor/whistle").install "whistle.cact" }
    ENV["SWIFT_BUILD_FLAGS"] = "--disable-sandbox"
    system "scripts/build-app.sh"
    prefix.install "build/Hark.app"
    bin.write_exec_script prefix/"Hark.app/Contents/MacOS/Hark"
  end

  def caveats
    <<~EOS
      To add Hark to your Applications folder (so Spotlight and Launch at Login find it):
        ln -sf #{opt_prefix}/Hark.app /Applications/Hark.app

      Then open it, and grant Microphone and Accessibility when asked.
    EOS
  end

  test do
    # One second of 16 kHz mono silence: exercises file decoding, model load and the engine.
    samples = 16_000
    header = ["RIFF", 36 + (samples * 2), "WAVE", "fmt ", 16, 1, 1, 16_000, 32_000, 2, 16, "data", samples * 2]
    (testpath/"silence.wav").binwrite(header.pack("a4Va4a4VvvVVvva4V") + ("\0" * samples * 2))
    output = shell_output("#{bin}/Hark --transcribe #{testpath}/silence.wav")
    assert_match '"text":""', output
    assert_match '"audio_seconds":1', output
  end
end
