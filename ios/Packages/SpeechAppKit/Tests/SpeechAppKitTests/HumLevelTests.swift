import Testing
@testable import SpeechAppKit

@Suite("Hum level")
struct HumLevelTests {
    /// One tap buffer is about 20ms. 250 buffers is five seconds, 400 is eight.
    private static let buffersPerSecond = 50

    @Test("a hum held past five seconds stays up")
    func heldHum() {
        var level = HumLevel()
        level.playbackRMS = 0.48
        var atFiveSeconds = 0.0
        var atEightSeconds = 0.0
        for step in 1 ... (8 * Self.buffersPerSecond) {
            let value = level.observe(micRMS: 0.14)
            if step == 5 * Self.buffersPerSecond { atFiveSeconds = value }
            atEightSeconds = value
        }
        #expect(atFiveSeconds > 0.5)
        #expect(abs(atEightSeconds - atFiveSeconds) < 0.05)
    }

    @Test("the speaker alone does not lift the field")
    func speakerLeak() {
        var level = HumLevel()
        level.playbackRMS = 0.48
        let micFromSpeaker = 0.48 * HumLevel.speakerLeak
        var value = 0.0
        for _ in 0 ..< (8 * Self.buffersPerSecond) {
            value = level.observe(micRMS: micFromSpeaker)
        }
        #expect(value == 0)
    }

    @Test("before the tone, a voice still lifts the field")
    func beforeTone() {
        var level = HumLevel()
        let value = level.observe(micRMS: 0.08)
        #expect(value > 0.3)
    }
}
