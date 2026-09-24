import Testing
@testable import SpeechAppKit

@Suite("Conversation pause time")
struct ConversationPauseTimeTests {
    @Test("sums gaps of at least 250ms between fixture ranges")
    func sumsQualifyingGaps() {
        let pause = ConversationPauseTime.seconds(from: [
            ConversationSpeechInterval(start: 0, end: 1),
            ConversationSpeechInterval(start: 1.125, end: 2),
            ConversationSpeechInterval(start: 2.5, end: 3),
        ])
        #expect(pause == 0.5)
    }

    @Test("overlapping ranges merge before measuring gaps")
    func mergesBeforeGaps() {
        let pause = ConversationPauseTime.seconds(from: [
            ConversationSpeechInterval(start: 0, end: 2),
            ConversationSpeechInterval(start: 1, end: 3),
            ConversationSpeechInterval(start: 5, end: 6),
        ])
        #expect(pause == 2)
    }

    @Test("a single range has no pause time")
    func singleRange() {
        let pause = ConversationPauseTime.seconds(from: [
            ConversationSpeechInterval(start: 0, end: 4),
        ])
        #expect(pause == 0)
    }

    @Test("counts gaps of at least 250ms")
    func countsQualifyingGaps() {
        let count = ConversationPauseTime.count(from: [
            ConversationSpeechInterval(start: 0, end: 1),
            ConversationSpeechInterval(start: 1.3, end: 2),
            ConversationSpeechInterval(start: 2.5, end: 3),
        ])
        #expect(count == 2)
    }

    @Test("a single range has no pause count")
    func singleRangeCount() {
        let count = ConversationPauseTime.count(from: [
            ConversationSpeechInterval(start: 0, end: 4),
        ])
        #expect(count == 0)
    }
}
