import Testing
@testable import SpeechAppKit

@Suite("Monologue phonation-time ratio")
struct MonologuePhonationTests {
    @Test("speech over wall is the ratio")
    func ratio() {
        let spoken = ConversationSpeechMetrics.unionDuration([
            ConversationSpeechInterval(start: 0, end: 6),
            ConversationSpeechInterval(start: 8, end: 10),
        ])
        #expect(MonologuePhonation.ratio(spoken: spoken, wall: 10) == 0.8)
    }

    @Test("zero wall is nil")
    func zeroWall() {
        #expect(MonologuePhonation.ratio(spoken: 4, wall: 0) == nil)
    }

    @Test("paused clock is already excluded from wall by the caller")
    func leftoverCeilingStillValid() {
        // 90s talk under a 240s ceiling still has a ratio.
        #expect(MonologuePhonation.ratio(spoken: 70, wall: 90) == 70.0 / 90.0)
    }
}
