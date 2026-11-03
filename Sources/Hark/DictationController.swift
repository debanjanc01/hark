import AppKit
import HarkCore
import os

/// Hold the hotkey → record → release → transcribe → paste.
@MainActor
final class DictationController {
    private enum State {
        case loading, idle, listening(since: ContinuousClock.Instant), transcribing
    }

    private static let minimumDuration: Duration = .milliseconds(300)
    private static let log = Logger(subsystem: "io.github.debanjanc01.hark", category: "dictation")

    private let settings = Settings()
    private let recorder = AudioRecorder()
    private let hotkeys: HotkeyMonitor
    private let statusItem: StatusItemController
    private let indicator = IndicatorPanel()
    private var transcriber: Transcriber?
    private var state = State.loading
    private var animation: Timer?
    private var permissionPoll: Timer?

    init() {
        hotkeys = HotkeyMonitor(hotkey: settings.hotkey)
        statusItem = StatusItemController(settings: settings)
        hotkeys.onPress = { [unowned self] in startListening() }
        hotkeys.onRelease = { [unowned self] in finishListening() }
        hotkeys.onCancel = { [unowned self] in cancelListening() }
        statusItem.onSettingsChanged = { [unowned self] in hotkeys.hotkey = settings.hotkey }
    }

    func start() {
        loadModel()
        Task { await requestPermissions() }
    }

    // MARK: Setup

    private func loadModel() {
        guard let url = Self.modelURL() else {
            fail("Speech model not found. Reinstall Hark.")
            return
        }
        Task.detached(priority: .userInitiated) {
            let result = Result { try Transcriber(modelURL: url) }
            await MainActor.run { [self] in
                switch result {
                case .success(let transcriber):
                    self.transcriber = transcriber
                    state = .idle
                    refreshStatus()
                case .failure(let error):
                    fail(error.localizedDescription)
                }
            }
        }
    }

    /// The bundled model, or `HARK_MODEL` / `vendor/` when running from a checkout.
    nonisolated static func modelURL() -> URL? {
        if let path = ProcessInfo.processInfo.environment["HARK_MODEL"] {
            return URL(fileURLWithPath: path)
        }
        if let url = Bundle.main.url(forResource: "whistle", withExtension: "cact") {
            return url
        }
        let checkout = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("vendor/whistle/whistle.cact")
        return FileManager.default.fileExists(atPath: checkout.path) ? checkout : nil
    }

    private func requestPermissions() async {
        if !Permission.microphone.isGranted { await Permission.microphone.request() }
        if !Permission.accessibility.isGranted { await Permission.accessibility.request() }
        if !hotkeys.start() {
            await Permission.inputMonitoring.request()
            // macOS doesn't notify when Input Monitoring is granted, so retry until it is.
            permissionPoll = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [unowned self] _ in
                MainActor.assumeIsolated {
                    guard hotkeys.start() else { return }
                    permissionPoll?.invalidate()
                    permissionPoll = nil
                    refreshStatus()
                }
            }
        }
        refreshStatus()
    }

    // MARK: Dictation

    private func startListening() {
        guard case .idle = state else { return }
        guard Permission.microphone.isGranted else {
            Task { await Permission.microphone.request() }
            return
        }
        do {
            try recorder.start()
        } catch {
            Self.log.error("Could not start recording: \(error.localizedDescription, privacy: .public)")
            if settings.showsIndicator { indicator.showMessage("Mic unavailable") }
            return
        }
        state = .listening(since: .now)
        if settings.showsIndicator { indicator.showListening() }
        startAnimation { [unowned self] in
            let level = recorder.level
            statusItem.setIcon(.listening(level: level))
            if settings.showsIndicator { indicator.update(level: level) }
        }
    }

    private func finishListening() {
        guard case .listening(let since) = state else { return }
        let (samples, heardSpeech) = recorder.stop()
        stopAnimation()

        // Skip accidental taps, and recordings where only background sound (or nobody) was heard.
        guard ContinuousClock.now - since >= Self.minimumDuration, let transcriber else {
            returnToIdle()
            return
        }
        guard heardSpeech else {
            returnToIdle(message: "No speech heard")
            return
        }

        state = .transcribing
        if settings.showsIndicator { indicator.showTranscribing() }
        let start = ContinuousClock.now
        startAnimation { [unowned self] in
            let phase = (ContinuousClock.now - start) / .seconds(1)
            statusItem.setIcon(.transcribing(phase: phase.truncatingRemainder(dividingBy: 1)))
        }

        let language = settings.language
        let keywords = settings.keywords
        Task(priority: .userInitiated) {
            do {
                let transcript = try await transcriber.transcribe(samples, language: language, keywords: keywords)
                let text = transcript.text.trimmingCharacters(in: .whitespacesAndNewlines)
                Self.log.info("""
                    Transcribed \(Double(samples.count) / Double(Transcriber.sampleRate), format: .fixed(precision: 1))s \
                    in \(ContinuousClock.now - start, privacy: .public): \(text, privacy: .private)
                    """)
                if text.isEmpty {
                    returnToIdle(message: "No speech heard")
                } else {
                    returnToIdle()
                    await TextInserter.insert(text)
                }
            } catch {
                Self.log.error("\(error.localizedDescription, privacy: .public)")
                returnToIdle(message: "Transcription failed")
            }
        }
    }

    private func cancelListening() {
        guard case .listening = state else { return }
        _ = recorder.stop()
        returnToIdle()
    }

    private func returnToIdle(message: String? = nil) {
        stopAnimation()
        state = .idle
        if let message, settings.showsIndicator {
            indicator.showMessage(message)
        } else {
            indicator.hide()
        }
        refreshStatus()
    }

    // MARK: UI

    private func startAnimation(_ frame: @escaping @MainActor () -> Void) {
        stopAnimation()
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { _ in
            MainActor.assumeIsolated { frame() }
        }
        RunLoop.main.add(timer, forMode: .common)  // keep animating while the menu is open
        animation = timer
    }

    private func stopAnimation() {
        animation?.invalidate()
        animation = nil
    }

    private func refreshStatus() {
        guard case .idle = state else { return }
        let missing = Permission.allCases.filter { !$0.isGranted }
        if missing.isEmpty {
            statusItem.status = "Hark is ready"
            statusItem.setIcon(.idle)
        } else {
            statusItem.status = "Needs \(missing.map(\.displayName).formatted()) access"
            statusItem.setIcon(.needsAttention)
        }
    }

    private func fail(_ message: String) {
        Self.log.fault("\(message, privacy: .public)")
        statusItem.status = message
        statusItem.setIcon(.needsAttention)
    }
}
