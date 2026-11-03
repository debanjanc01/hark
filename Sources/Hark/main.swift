import AppKit
import HarkCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: DictationController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = DictationController()
        controller.start()
        self.controller = controller
    }

    /// Opening Hark while it runs shows the setup window: the menu bar icon may be hidden.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        controller?.showSetup()
        return false
    }
}

/// `Hark --transcribe <audio file> [--language en] [--keywords "Priya,Kubernetes"] [--repeat N]`:
/// transcribes a file and prints the result with timings as JSON.
func transcribeFromCommandLine(_ arguments: [String]) async -> Int32 {
    guard let index = arguments.firstIndex(of: "--transcribe"), index + 1 < arguments.count else { return 2 }
    func value(_ flag: String) -> String? { arguments.firstIndex(of: flag).flatMap { arguments[safe: $0 + 1] } }
    let repeats = value("--repeat").flatMap(Int.init) ?? 1
    let language = value("--language")
    let keywords = value("--keywords")?.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } ?? []
    do {
        let clock = ContinuousClock()
        var transcriber: Transcriber?
        let loadTime = try clock.measure {
            transcriber = try Transcriber(modelURL: DictationController.modelURL() ?? URL(fileURLWithPath: "whistle.cact"))
        }
        let samples = try AudioFile.samples(at: URL(fileURLWithPath: arguments[index + 1]))
        var transcript: Transcript?
        var runs: [Double] = []
        for _ in 0..<max(1, repeats) {
            let start = clock.now
            transcript = try await transcriber!.transcribe(samples, language: language, keywords: keywords)
            runs.append((clock.now - start) / .milliseconds(1))
        }
        let result: [String: Any] = [
            "text": transcript?.text ?? "",
            "language": transcript?.language ?? "",
            "audio_seconds": Double(samples.count) / Double(Transcriber.sampleRate),
            "load_ms": loadTime / .milliseconds(1),
            "transcribe_ms": runs,
        ]
        let json = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: json, as: UTF8.self))
        return 0
    } catch {
        FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
        return 1
    }
}

/// `Hark --mic-check`: measures how fast recording starts and that the mic is released after.
@MainActor
func micCheck() async -> Int32 {
    for permission in Permission.allCases {
        print("\(permission.displayName): \(permission.isGranted ? "granted" : "NOT granted")")
    }
    let recorder = AudioRecorder()
    recorder.prepare()
    print("mic in use before recording: \(AudioRecorder.isMicrophoneInUse)")
    for trial in 1...3 {
        let clock = ContinuousClock()
        let start = clock.now
        do { try recorder.start() } catch {
            print("error: \(error.localizedDescription)")
            return 1
        }
        while recorder.capturedSeconds == 0, clock.now - start < .seconds(2) {
            try? await Task.sleep(for: .milliseconds(2))
        }
        let firstAudio = clock.now - start
        try? await Task.sleep(until: start + .seconds(1))
        let (samples, speechFrames) = recorder.stop()
        try? await Task.sleep(for: .milliseconds(300))
        print("trial \(trial): first audio after \(firstAudio.formatted(.units(allowed: [.milliseconds]))), "
              + "\(samples.count * 1000 / Transcriber.sampleRate) ms captured in 1 s, \(speechFrames) speech frames, "
              + "mic released: \(!AudioRecorder.isMicrophoneInUse)")
    }
    return 0
}

/// Hark shows no menu bar of its own, but its text fields (the try-it box, Custom Words)
/// still need the Edit menu's shortcuts: ⌘V is how Hark pastes, even into itself.
@MainActor
func editMenu() -> NSMenu {
    let edit = NSMenu(title: "Edit")
    for (title, action, key) in [("Undo", "undo:", "z"), ("Redo", "redo:", "Z"), ("Cut", "cut:", "x"),
                                 ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
        edit.addItem(withTitle: title, action: Selector(action), keyEquivalent: key)
    }
    let menu = NSMenu()
    menu.addItem(NSMenuItem())  // the app menu
    menu.addItem(withTitle: "Edit", action: nil, keyEquivalent: "").submenu = edit
    return menu
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

if CommandLine.arguments.contains("--mic-check") {
    Task { @MainActor in exit(await micCheck()) }
    dispatchMain()
}

if CommandLine.arguments.contains("--transcribe") {
    // Read the arguments here: Swift 6.0 rejects touching CommandLine from inside the task.
    Task(priority: .userInitiated) { [arguments = CommandLine.arguments] in
        exit(await transcribeFromCommandLine(arguments))
    }
    dispatchMain()
}

// Only one Hark at a time: two would fight over the hotkey and the menu bar. If another
// copy (say, an older build) is already running, bring that one forward instead.
if let id = Bundle.main.bundleIdentifier,
   let running = NSRunningApplication.runningApplications(withBundleIdentifier: id)
       .first(where: { $0.processIdentifier != getpid() }),
   let url = running.bundleURL {
    NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, _ in exit(0) }
    dispatchMain()
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)  // menu bar only, no Dock icon
    app.mainMenu = editMenu()
    app.run()
}
