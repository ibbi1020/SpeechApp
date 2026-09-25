import Testing
@testable import SpeechAppKit

@Suite("Conversation phases")
struct ConversationPhaseTests {
    @Test("crisis and dropped never wrap")
    func terminalExcludesWrapping() {
        #expect(ConversationPhase.crisis.entersWrapping == false)
        #expect(ConversationPhase.dropped.entersWrapping == false)
        #expect(ConversationPhase.talking.entersWrapping == true)
    }

    @Test("pause button only while talking or paused")
    func pauseButtonPhases() {
        #expect(ConversationPhase.talking.showsPauseButton == true)
        #expect(ConversationPhase.paused.showsPauseButton == true)
        #expect(ConversationPhase.connecting.showsPauseButton == false)
        #expect(ConversationPhase.wrapping.showsPauseButton == false)
        #expect(ConversationPhase.countdown.showsPauseButton == false)
        #expect(ConversationPhase.dropped.showsPauseButton == false)
    }

    @Test("userStop has no spoken close")
    func userStopSilent() {
        #expect(ConversationEndReason.userStop.speaksClose == false)
        #expect(ConversationEndReason.wrap.speaksClose == true)
        #expect(ConversationEndReason.pauseTTL.speaksClose == false)
        #expect(ConversationEndReason.crisisReferral.speaksClose == false)
    }
}
