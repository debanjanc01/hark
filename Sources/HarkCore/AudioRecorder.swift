@preconcurrency import AVFoundation
import CoreAudio
import os

public enum AudioRecorderError: Error, LocalizedError {
    case noInputDevice
    case unsupportedFormat

    public var errorDescription: String? {
        switch self {
        case .noInputDevice: "No microphone is available."
        case .unsupportedFormat: "The microphone's audio format is not supported."
        }
    }
}

/// Records the default microphone as 16 kHz mono float samples while metering speech.
///
/// The audio engine is built ahead of time and paused between recordings: a fresh
/// engine takes 300+ ms to deliver audio, which clips the first word, while resuming
/// a prepared one takes ~150 ms. Pausing fully releases the mic (no orange dot).
/// The engine is rebuilt when the default input device changes.
@MainActor
public final class AudioRecorder {
    private let capture = Capture()
    private var engine: AVAudioEngine?
    private var engineDevice: AudioDeviceID?
    private var configurationObserver: (any NSObjectProtocol)?

    public init() {}

    /// Current speech level, 0...1 (see `VoiceMeter`). Safe to read while recording.
    public nonisolated var level: Float { capture.level }

    /// Seconds of audio captured so far in the current recording.
    public nonisolated var capturedSeconds: Double { capture.capturedSeconds }

    /// Whether the default input device is running for any app (drives the orange mic dot).
    public static var isMicrophoneInUse: Bool {
        guard let device = defaultInputDevice() else { return false }
        var running = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &running) == noErr && running != 0
    }

    /// Builds the audio engine so the next `start()` is fast. Doesn't turn the mic on.
    public func prepare() {
        _ = try? currentEngine()
    }

    public func start() throws {
        do {
            try startEngine()
        } catch {
            // A stale engine (e.g. after sleep or a device hiccup) can fail; retry once with a fresh one.
            discardEngine()
            try startEngine()
        }
    }

    private func startEngine() throws {
        let engine = try currentEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw AudioRecorderError.noInputDevice }
        guard let converter = AVAudioConverter(from: format, to: Capture.outputFormat) else {
            throw AudioRecorderError.unsupportedFormat
        }

        capture.begin(converter: converter, inputRate: format.sampleRate)
        input.installTap(onBus: 0, bufferSize: 512, format: format, block: Self.tapBlock(for: capture))
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw error
        }
    }

    /// Stops recording and returns the captured audio, plus how much of it was the person speaking.
    public func stop() -> (samples: [Float], speechFrames: Int) {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.pause()
        return capture.finish()
    }

    /// The tap runs on the audio thread, so its block must not inherit main-actor isolation.
    private nonisolated static func tapBlock(for capture: Capture) -> AVAudioNodeTapBlock {
        { buffer, _ in capture.append(buffer) }
    }

    private func currentEngine() throws -> AVAudioEngine {
        let device = Self.defaultInputDevice()
        if let engine, device == engineDevice { return engine }
        discardEngine()

        let engine = AVAudioEngine()
        _ = engine.inputNode  // creates the input audio unit for the current default device
        engine.prepare()
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.engineDevice = nil }  // rebuild before the next recording
        }
        self.engine = engine
        engineDevice = device
        return engine
    }

    private func discardEngine() {
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
        engine?.stop()
        engine = nil
        engineDevice = nil
        configurationObserver = nil
    }

    private static func defaultInputDevice() -> AudioDeviceID? {
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return status == noErr && device != kAudioObjectUnknown ? device : nil
    }
}

/// Converts and accumulates audio on the render thread; read from the main thread.
private final class Capture: Sendable {
    static let outputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(Transcriber.sampleRate),
                                            channels: 1, interleaved: false)!

    private struct State {
        var converter: AVAudioConverter?
        var ratio = 1.0
        var samples: [Float] = []
        var meter = VoiceMeter()
    }

    private let state = OSAllocatedUnfairLock(uncheckedState: State())

    var level: Float { state.withLockUnchecked { $0.meter.level } }
    var capturedSeconds: Double { state.withLockUnchecked { Double($0.samples.count) / Double(Transcriber.sampleRate) } }

    func begin(converter: AVAudioConverter, inputRate: Double) {
        state.withLockUnchecked {
            $0.converter = converter
            $0.ratio = Self.outputFormat.sampleRate / inputRate
            $0.samples.removeAll(keepingCapacity: true)
            $0.samples.reserveCapacity(Transcriber.sampleRate * 30)
            $0.meter.reset()
        }
    }

    func finish() -> (samples: [Float], speechFrames: Int) {
        state.withLockUnchecked { state in
            defer {
                state.samples = []
                state.converter = nil
            }
            return (state.samples, state.meter.speechFrames)
        }
    }

    // Runs on the audio render thread.
    func append(_ buffer: AVAudioPCMBuffer) {
        state.withLockUnchecked { state in
            guard let converter = state.converter else { return }
            let capacity = AVAudioFrameCount((Double(buffer.frameLength) * state.ratio).rounded(.up)) + 16
            guard let converted = AVAudioPCMBuffer(pcmFormat: Self.outputFormat, frameCapacity: capacity) else { return }

            // The input block runs synchronously inside convert(to:), on this thread.
            nonisolated(unsafe) var supplied = false
            var error: NSError?
            converter.convert(to: converted, error: &error) { _, status in
                if supplied {
                    status.pointee = .noDataNow
                    return nil
                }
                supplied = true
                status.pointee = .haveData
                return buffer
            }
            guard error == nil, let channel = converted.floatChannelData?[0] else { return }

            let samples = UnsafeBufferPointer(start: channel, count: Int(converted.frameLength))
            state.samples.append(contentsOf: samples)
            state.meter.feed(samples)
        }
    }
}
