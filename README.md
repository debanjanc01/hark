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
brew trust --cask debanjanc01/tap/hark
brew install --cask debanjanc01/tap/hark
open /Applications/Hark.app
```

The first line is Homebrew's [tap trust](https://docs.brew.sh/Tap-Trust): it lets Homebrew install Hark from this tap, and nothing else from it.

Hark isn't notarized by Apple yet, so macOS blocks the first launch. Go to System Settings → Privacy & Security, scroll down and click **Open Anyway**. You only do this once.

Or grab the zip from [Releases](https://github.com/debanjanc01/hark/releases/latest) and drag Hark to Applications (same one-time **Open Anyway**).

Installed Hark with `brew install debanjanc01/tap/hark` before? Switch with `brew uninstall hark && rm /Applications/Hark.app` (that removes the old link), then the commands above.

## Use it

1. Click where you want the text.
2. Hold **Right Option** and talk. A small pill shows *Listening…* with bars that follow your voice.
3. Let go. The text pops in.

Works in any app: your editor, terminal, browser, Slack, Claude Code. Dictate twice in a row and Hark adds the space between sentences for you.

From the menu bar icon, or the window you get by opening Hark again, you can change the hotkey (Right Option, Right Command or Fn), set the language, add **Custom Words** (names and jargon Hark keeps mishearing, like a teammate's name), hide the pill, or launch at login.

On first launch Hark opens a small window asking for **Microphone** (to hear you) and **Accessibility** (to notice the hotkey in any app and paste the text). Open Hark again anytime to bring that window back.

## Good to know

- **7 languages:** English, German, French, Spanish, Italian, Dutch and Polish. Defaults to your Mac's language, or switch to auto-detect.
- **Ignores the room.** Fan noise, hum and distant voices don't count as you talking, and if that's all Hark heard, nothing gets pasted. Someone talking right next to your mic can still get picked up, though.
- **Names and accents.** It's a small model, so it can trip on names ("Priya" → "Prea") and accent-dependent words. Add those to Custom Words and it gets them right.
- **The mic is only on while you hold the key.** Audio is never saved. Your clipboard is restored after pasting (if a paste fails, the text stays on it for you to paste by hand). More in [SECURITY.md](SECURITY.md).
- **Want the biggest model instead?** If you need the most accuracy on hard audio, many languages, or AI rewriting of what you said, a heavier app running a large model is the better pick. Hark is for fast, everyday dictation with the smallest footprint.

## Something off?

- **Nothing happens when I hold the key:** open Hark again. The window shows what's missing.
- **No menu bar icon:** your menu bar is full and macOS hid it behind the notch. Hold ⌘ and drag other icons off to make room.
- **"Couldn't paste":** no app took the text, usually because nothing you can type in was selected. It's on your clipboard: click where you want it and press ⌘V. If this happens everywhere, turn on Accessibility for Hark.
- **"No speech heard":** move a bit closer to the mic, and check the right input is picked in System Settings → Sound.
- **First word cut off, or not sure the mic works?** Run `/Applications/Hark.app/Contents/MacOS/Hark --mic-check`. It shows how fast recording starts (about 150 ms is normal).
- **Asked for permissions again after an update:** that's expected until Hark is signed by Apple, since macOS ties permissions to each build. Click **Allow…** in Hark's window again; it clears the old entry for you.

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
