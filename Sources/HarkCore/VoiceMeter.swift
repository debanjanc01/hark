import Accelerate

/// Measures how loudly *the person at the mic* is speaking, in 30 ms frames of 16 kHz audio.
///
/// A frame counts as near-field speech when all of these hold:
/// - it is `gateDB` louder than the room's running background level, so distant
///   voices, a TV or a fan don't register;
/// - most of its energy is in the voice band (150–4000 Hz), which rejects hiss, and some of it
///   is above 300 Hz where speech formants live, which rejects hum;
/// - its spectrum is peaky rather than flat (low spectral flatness), as voiced speech is.
///
/// `level` is 0 for anything else, and 0.25...1 for speech, scaled by loudness.
/// Not thread-safe: feed and read it from one thread or under a lock.
public struct VoiceMeter {
    public static let frameSize = 480  // 30 ms at 16 kHz

    public var gateDB: Float
    public private(set) var level: Float = 0
    /// How many 30 ms frames since the last `reset()` were near-field speech.
    public private(set) var speechFrames = 0
    /// Whether there was enough near-field speech to be worth transcribing. A few stray
    /// frames (a cough, a door) would otherwise make the model hallucinate ("Thank you.").
    public var heardSpeech: Bool { speechFrames >= Self.minimumSpeechFrames }
    public static let minimumSpeechFrames = 6  // 180 ms

    private static let fftSize = 512
    private static let binHz = Float(Transcriber.sampleRate) / Float(fftSize)
    private static let analysisBins = bins(from: 150, to: 8000)  // ignores rumble below 150 Hz
    private static let voiceBins = bins(from: 150, to: 4000)  // deep voices have strong harmonics below 250 Hz
    private static let formantBins = bins(from: 300, to: 4000)  // speech always has energy here; hum doesn't

    private let fft = vDSP.FFT(log2n: 9, radix: .radix2, ofType: DSPSplitComplex.self)!
    private let window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized,
                                     count: frameSize, isHalfWindow: false)
    private var pending: [Float] = []
    private var frame = [Float](repeating: 0, count: fftSize)
    private var real = [Float](repeating: 0, count: fftSize / 2)
    private var imag = [Float](repeating: 0, count: fftSize / 2)
    private var power = [Float](repeating: 0, count: fftSize / 2)
    private var logs = [Float](repeating: 0, count: voiceBins.count)
    private var roomDB: Float?
    /// Frames to skip at the start of a recording: the mic delivers near-silence while it
    /// wakes up, which would otherwise drag the room level far below the real one.
    private static let warmupFrameCount = 3
    private var warmupFrames = warmupFrameCount

    public init(gateDB: Float = 6) {
        self.gateDB = gateDB
        pending.reserveCapacity(4 * Self.frameSize)
    }

    /// Starts a new recording. The room's background level is kept: it's the best guess
    /// for the next recording too, and learning it from scratch every time made the start
    /// of each recording count room noise as speech.
    public mutating func reset() {
        pending.removeAll(keepingCapacity: true)
        level = 0
        speechFrames = 0
        warmupFrames = Self.warmupFrameCount
    }

    /// Feeds 16 kHz mono samples; `level` reflects the most recent complete frame.
    public mutating func feed(_ samples: UnsafeBufferPointer<Float>) {
        pending.append(contentsOf: samples)
        var start = 0
        while pending.count - start >= Self.frameSize {
            analyze(pending[start..<start + Self.frameSize])
            start += Self.frameSize
        }
        pending.removeFirst(start)
    }

    public mutating func feed(_ samples: [Float]) {
        samples.withUnsafeBufferPointer { feed($0) }
    }

    private mutating func analyze(_ samples: ArraySlice<Float>) {
        // Windowed, zero-padded power spectrum.
        vDSP.multiply(samples, window, result: &frame[0..<Self.frameSize])
        real.withUnsafeMutableBufferPointer { realPtr in
            imag.withUnsafeMutableBufferPointer { imagPtr in
                var split = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                frame.withUnsafeBufferPointer { samples in
                    samples.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: Self.fftSize / 2) {
                        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(Self.fftSize / 2))
                    }
                }
                fft.forward(input: split, output: &split)
                vDSP.squareMagnitudes(split, result: &power)
            }
        }

        let total = vDSP.sum(power[Self.analysisBins])
        let voice = vDSP.sum(power[Self.voiceBins])
        let formants = vDSP.sum(power[Self.formantBins])
        let db = 10 * log10(max(total, 1e-12))
        if warmupFrames > 0 {
            warmupFrames -= 1
            level = 0
            return
        }

        let room = roomDB ?? db
        let above = db - room - gateDB
        let isSpeech = above > 0
            && voice / max(total, 1e-12) > 0.6
            && formants / max(total, 1e-12) > 0.1
            && voiceFlatness() < 0.4
        level = isSpeech ? min(1, 0.25 + above / 18) : 0

        // Learn the background level from quiet frames only (never from speech or anything
        // loud): it falls quickly and rises slowly, so it settles on the room's steady noise.
        if above <= 0 {
            roomDB = room + (db - room) * (db < room ? 0.05 : 0.008)
        }
        if isSpeech { speechFrames += 1 }
    }

    /// Spectral flatness of the voice band (geometric over arithmetic mean):
    /// ~0.56 for white noise, much lower for voiced speech.
    private mutating func voiceFlatness() -> Float {
        let bins = Self.voiceBins
        vDSP.clip(power[bins], to: 1e-12...Float.greatestFiniteMagnitude, result: &logs)
        let mean = vDSP.mean(logs)
        vForce.log(logs, result: &logs)
        return exp(vDSP.mean(logs)) / mean
    }

    private static func bins(from low: Float, to high: Float) -> Range<Int> {
        // Bin 0 holds DC (and the packed Nyquist term), so start at 1 and stop below fftSize / 2.
        max(1, Int((low / binHz).rounded(.up)))..<min(fftSize / 2, Int((high / binHz).rounded(.down)) + 1)
    }
}
