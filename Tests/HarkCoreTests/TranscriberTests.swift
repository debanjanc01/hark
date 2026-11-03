import Testing
@testable import HarkCore

@Suite(.enabled(if: Fixtures.hasModel, "Run scripts/fetch-deps.sh to download the model"))
struct TranscriberTests {
    @Test func transcribesEnglishSpeech() async throws {
        let transcriber = try #require(Fixtures.transcriber)
        let audio = try Fixtures.speech("The quick brown fox jumps over the lazy dog.")
        let transcript = try await transcriber.transcribe(audio, language: "en")
        #expect(transcript.text.lowercased().contains("quick brown fox"))
        #expect(transcript.language == "en")
    }

    @Test func detectsLanguageWhenNotGiven() async throws {
        let transcriber = try #require(Fixtures.transcriber)
        let audio = try Fixtures.speech("Hello, this is a test of automatic language detection.")
        let transcript = try await transcriber.transcribe(audio)
        #expect(transcript.language == "en")
    }

    @Test func silenceGivesEmptyText() async throws {
        let transcriber = try #require(Fixtures.transcriber)
        let transcript = try await transcriber.transcribe(Fixtures.silence(seconds: 1))
        #expect(transcript.text.isEmpty)
    }

    @Test func handlesEmptyInput() async throws {
        let transcriber = try #require(Fixtures.transcriber)
        let transcript = try await transcriber.transcribe([])
        #expect(transcript.text.isEmpty)
    }

    @Test func handlesAudioLongerThanOneWindow() async throws {
        let transcriber = try #require(Fixtures.transcriber)
        // The engine decodes in 30 s windows; make sure the output buffer grows to fit.
        let phrase = try Fixtures.speech("Testing a long dictation that spans more than one window.")
        let audio = Array(repeating: phrase + Fixtures.silence(seconds: 0.5), count: 12).flatMap { $0 }
        #expect(audio.count > 30 * Transcriber.sampleRate)
        let transcript = try await transcriber.transcribe(audio, language: "en")
        #expect(transcript.text.lowercased().contains("dictation"))
    }
}
