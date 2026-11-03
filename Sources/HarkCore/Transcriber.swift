import CNeedle
import Foundation

/// The result of one transcription.
public struct Transcript: Sendable, Equatable, Decodable {
    public let text: String
    /// ISO 639-1 code of the language used, or empty for silence/noise.
    public let language: String
    /// Milliseconds until the first token was decoded.
    public let ttftMs: Double
    /// Decoder throughput after the first token.
    public let decodeTps: Double
}

public enum TranscriberError: Error, Equatable, LocalizedError {
    case modelLoadFailed(String)
    case transcriptionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .modelLoadFailed(let reason): "Could not load the speech model: \(reason)"
        case .transcriptionFailed(let reason): "Transcription failed: \(reason)"
        }
    }
}

/// On-device speech-to-text with the Whistle model, via the Needle C engine.
///
/// The engine keeps one process-global, non-thread-safe speech model, so create a
/// single `Transcriber` per process; actor isolation serializes every call into it.
public actor Transcriber {
    public static let sampleRate = 16_000
    public static let languages = ["en", "de", "fr", "es", "it", "nl", "pl"]

    /// Output JSON grows with the audio length; the engine needs roughly 4 KB per second.
    private static let outputBytesPerSecond = 4096
    private var output = [CChar](repeating: 0, count: 64 * 1024)

    public init(modelURL: URL) throws {
        let model = try Data(contentsOf: modelURL, options: .alwaysMapped)
        let status = model.withUnsafeBytes { bytes in
            needle_load(bytes.bindMemory(to: UInt8.self).baseAddress, UInt64(bytes.count))
        }
        guard status >= 0 else { throw TranscriberError.modelLoadFailed(Self.lastError()) }
    }

    /// Transcribes 16 kHz mono float PCM in [-1, 1].
    /// - Parameters:
    ///   - language: one of `languages`, or nil to detect it.
    ///   - keywords: words or phrases to bias decoding towards.
    public func transcribe(_ samples: [Float], language: String? = nil, keywords: [String] = []) throws -> Transcript {
        let needed = samples.count / Self.sampleRate * Self.outputBytesPerSecond + 4096
        if output.count < needed {
            output = [CChar](repeating: 0, count: needed)
        }
        let keywordList = keywords.isEmpty ? nil : keywords.joined(separator: "\n")
        let status = Self.run(samples, language: language, keywords: keywordList, output: &output)
        guard status >= 0 else { throw TranscriberError.transcriptionFailed(Self.lastError()) }

        let json = output.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do {
            return try decoder.decode(Transcript.self, from: Data(json.utf8))
        } catch {
            throw TranscriberError.transcriptionFailed("unexpected engine output")
        }
    }

    private static func run(_ samples: [Float], language: String?, keywords: String?,
                            output: inout [CChar]) -> Int32 {
        samples.withUnsafeBufferPointer { pcm in
            withOptionalCString(language) { language in
                withOptionalCString(keywords) { keywords in
                    output.withUnsafeMutableBufferPointer { out in
                        needle_transcribe(pcm.baseAddress, Int32(pcm.count), language, keywords, 0,
                                          out.baseAddress, Int32(out.count))
                    }
                }
            }
        }
    }

    private static func lastError() -> String {
        needle_last_error().map { String(cString: $0) } ?? "unknown error"
    }
}

private func withOptionalCString<R>(_ string: String?, _ body: (UnsafePointer<CChar>?) -> R) -> R {
    guard let string else { return body(nil) }
    return string.withCString(body)
}
