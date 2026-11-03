# Releasing

1. Bump `VERSION`, commit, push.
2. `git tag v$(cat VERSION) && git push --tags`. CI tests, builds and publishes a GitHub release with `Hark-x.y.z.zip` and its `.sha256`, then builds a Homebrew bottle (a prebuilt Hark) and adds it to the release.
3. In [debanjanc01/homebrew-tap](https://github.com/debanjanc01/homebrew-tap), update `Formula/hark.rb` (template: `packaging/homebrew/hark.rb`):
   - `url` and `sha256`, with the hash from
     `curl -sL https://github.com/debanjanc01/hark/archive/refs/tags/vX.Y.Z.tar.gz | shasum -a 256`
   - the `bottle` block, copied from the summary of the release workflow's `bottle` job.

Ship the formula with the bottle block in the same commit: without it, everyone builds Hark from source again (about a minute, and it needs Xcode's tools).

## Signed builds (optional)

To skip the "Open Anyway" step for downloads, sign and notarize with an Apple Developer account by adding these repo secrets: `MACOS_CERTIFICATE` (base64 Developer ID .p12), `MACOS_CERTIFICATE_PASSWORD`, `CODESIGN_IDENTITY`, `APPLE_ID`, `APPLE_TEAM_ID`, `APPLE_APP_PASSWORD`. The release workflow picks them up automatically.
