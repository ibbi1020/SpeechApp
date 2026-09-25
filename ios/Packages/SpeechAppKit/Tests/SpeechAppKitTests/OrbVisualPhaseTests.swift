import Testing
@testable import SpeechAppKit

struct OrbVisualPhaseTests {
    @Test("conversation countdown and connecting are loading")
    func conversationLoading() {
        #expect(
            OrbVisualPhase.conversation(
                phase: .countdown,
                isCountdown: true,
                floor: .partner,
                agentSpeaking: false
            ) == .connecting
        )
        #expect(
            OrbVisualPhase.conversation(
                phase: .connecting,
                isCountdown: false,
                floor: .partner,
                agentSpeaking: false
            ) == .connecting
        )
    }

    @Test("conversation pause and quiet gaps stay user speaking")
    func conversationUserSpeaking() {
        #expect(
            OrbVisualPhase.conversation(
                phase: .paused,
                isCountdown: false,
                floor: .partner,
                agentSpeaking: false
            ) == .listening
        )
        #expect(
            OrbVisualPhase.conversation(
                phase: .talking,
                isCountdown: false,
                floor: .user,
                agentSpeaking: false
            ) == .listening
        )
        #expect(
            OrbVisualPhase.conversation(
                phase: .talking,
                isCountdown: false,
                floor: .partner,
                agentSpeaking: false
            ) == .listening
        )
    }

    @Test("conversation partner audio and partner wrap are AI speaking")
    func conversationAISpeaking() {
        #expect(
            OrbVisualPhase.conversation(
                phase: .talking,
                isCountdown: false,
                floor: .partner,
                agentSpeaking: true
            ) == .speaking
        )
        #expect(
            OrbVisualPhase.conversation(
                phase: .wrapping,
                isCountdown: false,
                floor: .partner,
                agentSpeaking: false
            ) == .speaking
        )
        #expect(
            OrbVisualPhase.conversation(
                phase: .wrapping,
                isCountdown: false,
                floor: .user,
                agentSpeaking: false
            ) == .listening
        )
    }

    @Test("monologue prepare is loading; take and pause are user speaking")
    func monologue() {
        #expect(OrbVisualPhase.monologue(isPreparing: true, phase: .planning) == .connecting)
        #expect(OrbVisualPhase.monologue(isPreparing: false, phase: .taking) == .listening)
        #expect(OrbVisualPhase.monologue(isPreparing: false, phase: .paused) == .listening)
    }
}
