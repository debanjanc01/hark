import Foundation
@testable import HarkCore

enum Fixtures {
    static let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    static let modelURL = packageRoot.appendingPathComponent("vendor/whistle/whistle.cact")

    static var hasModel: Bool { FileManager.default.fileExists(atPath: modelURL.path) }

    /// One shared transcriber: the engine holds a single process-global model.
    static let transcriber: Transcriber? = try? Transcriber(modelURL: modelURL)

    /// Synthesizes speech with macOS `say` as 16 kHz mono samples.
    static func speech(_ text: String) throws -> [Float] {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("hark-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }

        let say = Process()
        say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        // HARK_TEST_VOICE picks a specific system voice (e.g. to reproduce a CI-only failure).
        let voice = ProcessInfo.processInfo.environment["HARK_TEST_VOICE"].map { ["-v", $0] } ?? []
        say.arguments = voice + ["-o", url.path, "--data-format=LEF32@16000", text]
        try say.run()
        say.waitUntilExit()
        return try AudioFile.samples(at: url)
    }

    static func silence(seconds: Double) -> [Float] {
        [Float](repeating: 0, count: Int(seconds * Double(Transcriber.sampleRate)))
    }

    static func whiteNoise(seconds: Double, rms: Float) -> [Float] {
        var generator = SystemRandomNumberGenerator()
        // Uniform noise in [-a, a] has RMS a/√3.
        let amplitude = rms * 3.0.squareRoot().float
        return (0..<Int(seconds * Double(Transcriber.sampleRate))).map { _ in
            Float.random(in: -amplitude...amplitude, using: &generator)
        }
    }

    /// Mains hum: 50 Hz with harmonics, like a fan or a ground loop.
    static func hum(seconds: Double, amplitude: Float) -> [Float] {
        (0..<Int(seconds * Double(Transcriber.sampleRate))).map { i in
            let t = Float(i) / Float(Transcriber.sampleRate)
            return amplitude * (sin(2 * .pi * 50 * t) + 0.5 * sin(2 * .pi * 100 * t) + 0.25 * sin(2 * .pi * 150 * t))
        }
    }

    static func rms(_ samples: [Float]) -> Float {
        (samples.reduce(0) { $0 + $1 * $1 } / Float(max(samples.count, 1))).squareRoot()
    }

    static func scaled(_ samples: [Float], toRMS target: Float) -> [Float] {
        let gain = target / max(rms(samples), 1e-9)
        return samples.map { $0 * gain }
    }

    /// Adds `b` into `a` starting at `offset`, extending as needed.
    static func mix(_ a: [Float], _ b: [Float], at offset: Int = 0) -> [Float] {
        var out = a + [Float](repeating: 0, count: max(0, offset + b.count - a.count))
        for (i, sample) in b.enumerated() { out[offset + i] += sample }
        return out
    }
}

private extension Double {
    var float: Float { Float(self) }
}
