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
}

/// `Hark --transcribe <audio file> [--repeat N]`: transcribes a file and prints JSON timings.
func transcribeFromCommandLine(_ arguments: [String]) async -> Int32 {
    guard let index = arguments.firstIndex(of: "--transcribe"), index + 1 < arguments.count else { return 2 }
    let repeats = arguments.firstIndex(of: "--repeat").flatMap { Int(arguments[safe: $0 + 1] ?? "") } ?? 1
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
            transcript = try await transcriber!.transcribe(samples)
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

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

if CommandLine.arguments.contains("--transcribe") {
    Task(priority: .userInitiated) { exit(await transcribeFromCommandLine(CommandLine.arguments)) }
    dispatchMain()
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)  // menu bar only, no Dock icon
    app.run()
}
