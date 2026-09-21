import Testing
@testable import SpeechAppKit

@Suite("Conversation cues")
struct ConversationCueTests {
    @Test("open instructions include frozen prefix and stance")
    func openHasPrefix() {
        let text = ConversationCueAssembler.instructions(
            prefix: "PREFIX",
            stance: "STANCE: cats > dogs",
            cue: .open(question: "What did you have for breakfast?")
        )
        #expect(text.contains("PREFIX"))
        #expect(text.contains("STANCE: cats > dogs"))
        #expect(text.contains("What did you have for breakfast?"))
        #expect(text.contains("Do not announce a timer"))
    }

    @Test("cue-only string is rejected")
    func rejectsCueOnly() {
        let text = ConversationCueAssembler.instructions(
            prefix: "PREFIX",
            stance: "STANCE",
            cue: .wrapWarn
        )
        #expect(text.hasPrefix("PREFIX"))
        #expect(!text.hasPrefix("Answer them"))
    }
}
