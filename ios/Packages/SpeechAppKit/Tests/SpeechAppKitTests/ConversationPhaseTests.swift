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

    @Test("userStop has no spoken close")
    func userStopSilent() {
        #expect(ConversationEndReason.userStop.speaksClose == false)
        #expect(ConversationEndReason.wrap.speaksClose == true)
        #expect(ConversationEndReason.pauseTTL.speaksClose == false)
        #expect(ConversationEndReason.crisisReferral.speaksClose == false)
    }
}
