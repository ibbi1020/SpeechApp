import Testing
@testable import SpeechAppKit

@Suite("Conversation time spoken")
struct ConversationSpeechMetricsTests {
    @Test("union of overlapping fixture ranges is spoken time")
    func unionOverlappingRanges() {
        let metrics = ConversationSpeechMetrics.from(
            ranges: [
                ConversationSpeechInterval(start: 0, end: 2),
                ConversationSpeechInterval(start: 1, end: 3),
                ConversationSpeechInterval(start: 5, end: 6),
            ],
            claimedSpeechSeconds: 4
        )
        #expect(metrics.spokenSeconds == 4)
        #expect(metrics.coverage == 1)
        #expect(metrics.limitedAnalysis == false)
    }

    @Test("coverage below 0.7 marks limited analysis")
    func lowCoverageIsUncertain() {
        let metrics = ConversationSpeechMetrics.from(
            ranges: [ConversationSpeechInterval(start: 0, end: 2)],
            claimedSpeechSeconds: 10
        )
        #expect(metrics.spokenSeconds == 2)
        #expect(metrics.coverage == 0.2)
        #expect(metrics.limitedAnalysis == true)
    }

    @Test("coverage of 0.7 is not limited")
    func coverageThreshold() {
        let metrics = ConversationSpeechMetrics.from(
            ranges: [ConversationSpeechInterval(start: 0, end: 7)],
            claimedSpeechSeconds: 10
        )
        #expect(metrics.coverage == 0.7)
        #expect(metrics.limitedAnalysis == false)
    }
}
