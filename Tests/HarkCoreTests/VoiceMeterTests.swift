import Testing
@testable import HarkCore

struct VoiceMeterTests {
    /// Feeds audio in mic-callback-sized chunks and records `level` after each.
    private func levels(_ samples: [Float], meter: inout VoiceMeter, chunk: Int = 341) -> [Float] {
        stride(from: 0, to: samples.count, by: chunk).map { start in
            meter.feed(Array(samples[start..<min(start + chunk, samples.count)]))
            return meter.level
        }
    }

    @Test func silenceIsNotSpeech() {
        var meter = VoiceMeter()
        let output = levels(Fixtures.silence(seconds: 1), meter: &meter)
        #expect(output.allSatisfy { $0 == 0 })
        #expect(!meter.heardSpeech)
    }

    @Test func steadyNoiseIsNotSpeech() {
        var meter = VoiceMeter()
        let output = levels(Fixtures.whiteNoise(seconds: 2, rms: 0.05), meter: &meter)
        #expect(output.allSatisfy { $0 == 0 })
        #expect(!meter.heardSpeech)
    }

    @Test func loudHumIsNotSpeech() {
        var meter = VoiceMeter()
        let quiet = Fixtures.whiteNoise(seconds: 1, rms: 0.001)
        let hum = Fixtures.mix(Fixtures.whiteNoise(seconds: 1, rms: 0.001), Fixtures.hum(seconds: 1, amplitude: 0.3))
        _ = levels(quiet + hum, meter: &meter)
        #expect(!meter.heardSpeech)
    }

    @Test func nearSpeechRegistersOverQuietRoom() throws {
        var meter = VoiceMeter()
        let room = Fixtures.whiteNoise(seconds: 4, rms: 0.002)
        let voice = Fixtures.scaled(try Fixtures.speech("Testing one two three, can you hear me?"), toRMS: 0.05)
        let audio = Fixtures.mix(room, voice, at: Transcriber.sampleRate)

        let output = levels(audio, meter: &meter)
        let leadIn = output.prefix(output.count * 1 / 4 - 2)  // the first second: room only
        #expect(leadIn.allSatisfy { $0 == 0 })
        #expect(meter.heardSpeech)
        #expect(output.contains { $0 > 0.5 })
    }

    @Test func distantVoicesInTheRoomAreIgnored() throws {
        // Background conversation (a TV, a call nearby) shouldn't move the meter;
        // the person at the mic, ~12 dB louder, should. A distant voice reaches the
        // mic only a few dB above the room's ambient noise, so model it that way.
        let speech = Fixtures.scaled(
            try Fixtures.speech("We have several messages to go through, and the first one is about the schedule."),
            toRMS: 0.006)
        let background = Fixtures.mix(Fixtures.whiteNoise(seconds: Double(speech.count) / 16_000, rms: 0.008), speech)
        let backgroundLoop = background + background + background
        let near = Fixtures.scaled(try Fixtures.speech("Open the settings panel."), toRMS: 0.04)

        var backgroundOnly = VoiceMeter()
        let warmup = levels(backgroundLoop, meter: &backgroundOnly)
        let settled = warmup.suffix(warmup.count / 2)  // after the meter has learned the room
        #expect(Float(settled.filter { $0 > 0 }.count) / Float(settled.count) < 0.1)

        var withNear = VoiceMeter()
        let nearStart = background.count * 2
        let audio = Fixtures.mix(backgroundLoop, near, at: nearStart)
        let output = levels(audio, meter: &withNear, chunk: 341)
        let nearPart = output[(nearStart / 341)..<((nearStart + near.count) / 341)]
        #expect(nearPart.filter { $0 > 0 }.count > nearPart.count / 3)
    }

    @Test func resetClearsState() throws {
        var meter = VoiceMeter()
        meter.feed(Fixtures.mix(Fixtures.whiteNoise(seconds: 2, rms: 0.002),
                                Fixtures.scaled(try Fixtures.speech("Hello there."), toRMS: 0.05), at: 8000))
        #expect(meter.heardSpeech)
        meter.reset()
        #expect(!meter.heardSpeech)
        #expect(meter.level == 0)
    }
}
