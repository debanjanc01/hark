# Security

## What Hark does with your data

- **Audio never leaves your Mac.** Transcription runs on-device with the Whistle model.
  Hark contains no networking code, and the bundled Needle engine has none either.
- **The mic is only open while you hold the hotkey.** A new audio session is created per
  dictation and torn down when you let go; recordings are kept in memory only, never written to disk.
- **Transcripts are not logged.** Unified logging marks transcript text `private`, so it is
  redacted unless you explicitly enable private data logging.
- **Developer words.** Fixing these happens on your Mac. Words that sound like a term are checked
  against macOS's built-in spell checker, using the same system service as other apps.
- **Clipboard.** Hark pastes via the clipboard, marking the item transient/concealed
  (per [nspasteboard.org](http://nspasteboard.org)) so clipboard managers skip it, and restores
  your previous clipboard afterwards unless something else wrote to it in the meantime. If no app
  takes the text, it stays on the clipboard as a normal copy instead, so you can paste it by hand.
- **The hotkey listener is listen-only.** It reads modifier keys and key-down events to detect the
  hotkey, and never modifies or records keystrokes.

## Supply chain

`scripts/fetch-deps.sh` downloads the Needle engine and the Whistle model at pinned upstream
revisions and refuses any file whose SHA-256 doesn't match. Release builds are signed with the
hardened runtime; the only entitlement is microphone input.

## Reporting a vulnerability

Please use GitHub's [private vulnerability reporting](../../security/advisories/new) rather than
a public issue.
