@preconcurrency import AVFoundation
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
/// A fresh `AVAudioEngine` is created per recording, so switching mics (e.g. AirPods)
/// between recordings just works, and the mic is only open while recording.
public final class AudioRecorder: Sendable {
    private struct State {
        var engine: AVAudioEngine?
        var samples: [Float] = []
        var meter = VoiceMeter()
    }

    private let state = OSAllocatedUnfairLock(uncheckedState: State())
    private static let outputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                                    sampleRate: Double(Transcriber.sampleRate),
                                                    channels: 1, interleaved: false)!

    public init() {}

    /// Current speech level, 0...1 (see `VoiceMeter`).
    public var level: Float { state.withLockUnchecked { $0.meter.level } }

    public func start() throws {
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else { throw AudioRecorderError.noInputDevice }
        guard let converter = AVAudioConverter(from: inputFormat, to: Self.outputFormat) else {
            throw AudioRecorderError.unsupportedFormat
        }

        state.withLockUnchecked {
            $0.samples.removeAll(keepingCapacity: true)
            $0.samples.reserveCapacity(Transcriber.sampleRate * 30)
            $0.meter.reset()
        }
        let ratio = Self.outputFormat.sampleRate / inputFormat.sampleRate
        input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            self?.append(buffer, converter: converter, ratio: ratio)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw error
        }
        state.withLockUnchecked { $0.engine = engine }
    }

    /// Stops recording and returns the captured audio, plus whether the person spoke.
    public func stop() -> (samples: [Float], heardSpeech: Bool) {
        let engine = state.withLockUnchecked { state -> AVAudioEngine? in
            defer { state.engine = nil }
            return state.engine
        }
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        return state.withLockUnchecked { state in
            defer { state.samples = [] }
            return (state.samples, state.meter.heardSpeech)
        }
    }

    // Runs on the audio render thread.
    private func append(_ buffer: AVAudioPCMBuffer, converter: AVAudioConverter, ratio: Double) {
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 16
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
        state.withLockUnchecked {
            $0.samples.append(contentsOf: samples)
            $0.meter.feed(samples)
        }
    }
}
