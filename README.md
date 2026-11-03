<p align="center"><img src="docs/icon.png" width="112" alt=""></p>

<h1 align="center">Hark</h1>

<p align="center"><b>Local dictation for your Mac. 17 MB, total.</b><br>Hold a key, talk, let go. Your words show up wherever you're typing.</p>

---

Local dictation shouldn't need a gigabyte. Most offline dictation apps ship Whisper or Parakeet models that weigh 250 MB to 3 GB, and keep a chunk of that in memory all day.

Hark is the small one:

| | |
| --- | --- |
| **Whole app** | 17 MB. The app itself is 0.8 MB, the rest is the speech model. |
| **Memory when idle** | ~31 MB |
| **CPU when idle** | 0% |
| **Speed** | ~30 ms to turn a sentence into text, on the CPU |
| **Startup** | ready in ~0.1 s |
| **Network** | none. Nothing leaves your Mac. |

That's possible because of [Whistle](https://cactuscompute.com/blog/whistle), a 16 MB speech-to-text model from Cactus Compute. Hark is a thin native wrapper around it: no Electron, no Python, no bundled runtime, no background services.

## Install

Apple Silicon Mac, macOS 13 or newer.

```sh
brew install debanjanc01/tap/hark
ln -sf "$(brew --prefix)/opt/hark/Hark.app" /Applications/Hark.app
open /Applications/Hark.app
```

Or grab the zip from [Releases](https://github.com/debanjanc01/hark/releases/latest) and drag Hark to Applications. Since it isn't signed by Apple yet, macOS blocks the first launch: go to System Settings → Privacy & Security and hit **Open Anyway**. (Homebrew builds it on your Mac, so you skip this.)

## Use it

1. Click where you want the text.
2. Hold **Right Option** and talk. A small pill shows *Listening…* with bars that follow your voice.
3. Let go. The text pops in.

Works in any app: your editor, terminal, browser, Slack, Claude Code. Dictate twice in a row and Hark adds the space between sentences for you.

From the menu bar icon you can change the hotkey (Right Option, Right Command or Fn), set the language, hide the pill, launch at login, or add **Custom Words**: names and jargon Hark keeps mishearing (like a teammate's name).

On first launch macOS asks for **Microphone** (to hear you), **Input Monitoring** (to see the hotkey from any app) and **Accessibility** (to paste the text). If one is missing, the menu bar icon gets a slash and the menu links you to the right setting.

## Good to know

- **7 languages:** English, German, French, Spanish, Italian, Dutch and Polish. Defaults to your Mac's language, or switch to auto-detect.
- **Ignores the room.** Fan noise, hum and distant voices don't count as you talking, and if that's all Hark heard, nothing gets pasted. Someone talking right next to your mic can still get picked up, though.
- **Names and accents.** It's a small model, so it can trip on names ("Priya" → "Prea") and accent-dependent words. Add those to Custom Words and it gets them right.
- **The mic is only on while you hold the key.** Audio is never saved. Your clipboard is restored after pasting. More in [SECURITY.md](SECURITY.md).
- **Want the biggest model instead?** If you need the most accuracy on hard audio, many languages, or AI rewriting of what you said, a heavier app running a large model is the better pick. Hark is for fast, everyday dictation with the smallest footprint.

## Something off?

- **Nothing happens when I hold the key:** turn on Input Monitoring for Hark, then reopen it.
- **The pill shows but no text appears:** turn on Accessibility for Hark.
- **"No speech heard":** move a bit closer to the mic, and check the right input is picked in System Settings → Sound.
- **First word cut off, or not sure the mic works?** Run `/Applications/Hark.app/Contents/MacOS/Hark --mic-check`. It shows how fast recording starts (about 150 ms is normal).
- **Permissions broke after an update:** remove Hark from those three lists in System Settings and allow it again.

## Build it yourself

```sh
git clone https://github.com/debanjanc01/hark && cd hark
make test      # downloads the engine + model (pinned and checksum-checked), runs the tests
make install   # builds Hark.app, copies it to /Applications, opens it
```

`scripts/e2e/run.sh` tests the real app end to end: it holds the hotkey, plays speech through your speakers with `say`, and checks what gets pasted into a test window (run it in a quiet room, from a terminal with the three permissions).

Needs the Xcode Command Line Tools (`xcode-select --install`). It's plain Swift: `Sources/HarkCore` has the logic (recording, voice detection, transcription, hotkey, pasting), `Sources/Hark` is the menu bar app. You can also transcribe a file with `Hark.app/Contents/MacOS/Hark --transcribe note.m4a`.

## License

MIT. See [LICENSE](LICENSE), and [TERMS.md](TERMS.md) for the plain-English version. The Whistle model and Needle engine are by [Cactus Compute](https://cactuscompute.com), under Apache 2.0 ([notices](THIRD_PARTY_NOTICES.md)).
