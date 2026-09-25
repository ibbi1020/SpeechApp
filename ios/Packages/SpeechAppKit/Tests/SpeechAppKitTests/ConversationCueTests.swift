import Testing
@testable import SpeechAppKit

@Suite("Conversation cues")
struct ConversationCueTests {
    @Test("open instructions include frozen prefix and stance")
    func openHasPrefix() {
        let text = ConversationCueAssembler.instructions(
            prefix: "PREFIX",
            stance: "STANCE: cats > dogs",
            cue: .open(question: "Coffee or tea when you need to wake up?")
        )
        #expect(text.contains("PREFIX"))
        #expect(text.contains("STANCE: cats > dogs"))
        #expect(text.contains("Coffee or tea when you need to wake up?"))
        #expect(text.contains("Say only this question"))
        #expect(text.contains("no opinion, no stance"))
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
        #expect(!text.hasPrefix("Answer briefly"))
    }

    @Test("continue aside hands the floor and bans self-preference talk")
    func continueAsideFloorHand() {
        let aside = ConversationCueAssembler.continueAside
        #expect(aside.contains("at most three sentences"))
        #expect(aside.localizedCaseInsensitiveContains("hand the floor"))
        #expect(aside.localizedCaseInsensitiveContains("likes or wants"))
        #expect(aside.localizedCaseInsensitiveContains("one-word"))
        #expect(!aside.localizedCaseInsensitiveContains("answer them as you were going to"))
    }

    @Test("continue instructions stack prefix, stance, and aside")
    func continueInstructionsStack() {
        let text = ConversationCueAssembler.continueInstructions(
            prefix: "PREFIX",
            stance: "STANCE"
        )
        #expect(text.hasPrefix("PREFIX"))
        #expect(text.contains("STANCE"))
        #expect(text.contains(ConversationCueAssembler.continueAside))
        #expect(text.contains(ConversationCueAssembler.doNotAnnounceTimer))
    }

    @Test("wrap_warn keeps two-minute aside and caps floor-hand")
    func wrapWarnAside() {
        let text = ConversationCueAssembler.instructions(
            prefix: "PREFIX",
            stance: "STANCE",
            cue: .wrapWarn
        )
        #expect(text.contains("two minutes left"))
        #expect(text.localizedCaseInsensitiveContains("hand the floor at most once"))
        #expect(ConversationCueAssembler.heard(.wrapWarn, in: "About two minutes left — what next?"))
    }

    @Test("wrap_close forbids a new question")
    func wrapCloseNoQuestion() {
        let text = ConversationCueAssembler.instructions(
            prefix: "PREFIX",
            stance: "STANCE",
            cue: .wrapClose
        )
        #expect(text.contains("No new question"))
        #expect(!text.localizedCaseInsensitiveContains("hand the floor"))
        #expect(!text.localizedCaseInsensitiveContains("end with a question"))
    }

    @Test("frozen persona is anti-tutor and never always-asks")
    func frozenPersonaIdentityOnly() {
        let prefix = FrozenPersona.prefix
        #expect(prefix.localizedCaseInsensitiveContains("not a"))
        #expect(prefix.localizedCaseInsensitiveContains("teacher"))
        #expect(prefix.localizedCaseInsensitiveContains("no grammar"))
        #expect(prefix.localizedCaseInsensitiveContains("likes, wants"))
        #expect(!prefix.localizedCaseInsensitiveContains("end with a question"))
        #expect(!prefix.localizedCaseInsensitiveContains("always ask"))
        #expect(!prefix.localizedCaseInsensitiveContains("always end"))
    }
}
