<p align="center"><img src="docs/icon.png" width="112" alt=""></p>

<h1 align="center">Hark</h1>

<p align="center">Hold a key, talk, let go. Your words show up wherever you're typing.<br>Runs fully on your Mac. Nothing leaves it.</p>

---

Hark is a tiny menu bar app for dictating into any app: your editor, terminal, Slack, browser, Claude Code, whatever. Speech recognition is done on-device by [Whistle](https://cactuscompute.com/blog/whistle), a 17 MB model that turns a sentence into text in about 30 ms.

## Install

You need an Apple Silicon Mac on macOS 13 or newer.

**Homebrew** (easiest):

```sh
brew install debanjanc01/tap/hark
ln -sf "$(brew --prefix)/opt/hark/Hark.app" /Applications/Hark.app
open /Applications/Hark.app
```

**Or download** the zip from [Releases](https://github.com/debanjanc01/hark/releases/latest), unzip, and drag Hark to Applications. The first time you open it, macOS will block it because it isn't notarized yet. Go to System Settings → Privacy & Security and click **Open Anyway**. One time only.

## Use it

1. Click where you want the text.
2. Hold **Right Option** and talk. A little pill shows *Listening…* with bars that move with your voice.
3. Let go. It says *Transcribing…* for a blink, then the text pops in.

Pressed another key while holding Right Option (like ⌥←)? Hark figures you meant a shortcut and backs off.

From the menu bar icon you can change the hotkey (Right Option, Right Command or Fn), pick a language (English, German, French, Spanish, Italian, Dutch, Polish or auto), hide the pill, or start Hark at login.

## Permissions

macOS asks for three things the first time:

- **Microphone**: to hear you.
- **Input Monitoring**: to notice the hotkey from any app.
- **Accessibility**: to paste the text where your cursor is.

Missed one? The menu bar icon gets a slash through it, and the menu has a button that takes you to the right setting.

## Privacy

No accounts, no analytics, no network calls. The mic is only on while you hold the key, and audio is never saved. Your clipboard is put back after pasting, and clipboard managers are told to skip the dictated text. More in [SECURITY.md](SECURITY.md).

## Something off?

- **Nothing happens when I hold the key.** Turn on Input Monitoring for Hark, then quit and reopen it.
- **The pill shows but no text appears.** Turn on Accessibility for Hark.
- **"No speech heard".** Hark ignores background chatter and noise, so get a bit closer to the mic. Also check the right mic is picked in System Settings → Sound.
- **Permissions broke after an update.** Remove Hark from those three lists in System Settings and add it again. (Unsigned builds look like a new app to macOS each time.)

## Build it yourself

```sh
git clone https://github.com/debanjanc01/hark && cd hark
make test      # downloads the engine + model (pinned and checksum-checked), runs the tests
make install   # builds Hark.app, copies it to /Applications, opens it
```

You need the Xcode Command Line Tools (`xcode-select --install`). The code is plain Swift: `Sources/HarkCore` has the logic (recording, voice detection, transcription, hotkey, pasting) and `Sources/Hark` has the menu bar app.

The app binary can also transcribe a file, handy for scripts:

```sh
/Applications/Hark.app/Contents/MacOS/Hark --transcribe note.m4a
```

## Why Swift?

The model does the heavy lifting no matter what language calls it. Swift just makes everything around it lighter, and lets Hark talk to macOS directly. Compared with the same model via Python on an M4 Pro:

| | Hark | Python |
| --- | --- | --- |
| Model load | 11 ms | ~370 ms |
| 12 s of speech → text | 91 ms | 104 ms |
| Memory | ~48 MB | ~105 MB |

Run `scripts/benchmark.sh` to check on your machine.

## License

MIT. See [LICENSE](LICENSE), and [TERMS.md](TERMS.md) for the plain-English version. The Whistle model and Needle engine are by [Cactus Compute](https://cactuscompute.com) under Apache 2.0 ([notices](THIRD_PARTY_NOTICES.md)).
