# Releasing

1. Bump `VERSION`, commit, push.
2. `git tag v$(cat VERSION) && git push --tags`. CI tests, builds and publishes a GitHub release with `Hark-x.y.z.zip` and its `.sha256`.
3. In [debanjanc01/homebrew-tap](https://github.com/debanjanc01/homebrew-tap), update `version` and `sha256` in `Casks/hark.rb` (template: `packaging/homebrew/hark.rb`). The hash is in the release's `Hark-x.y.z.zip.sha256`.

## Signed builds (optional)

To skip the "Open Anyway" step for downloads, sign and notarize with an Apple Developer account by adding these repo secrets: `MACOS_CERTIFICATE` (base64 Developer ID .p12), `MACOS_CERTIFICATE_PASSWORD`, `CODESIGN_IDENTITY`, `APPLE_ID`, `APPLE_TEAM_ID`, `APPLE_APP_PASSWORD`. The release workflow picks them up automatically.
