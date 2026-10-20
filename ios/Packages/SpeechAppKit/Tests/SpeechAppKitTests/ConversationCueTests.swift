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
        #expect(text.contains("One short stake"))
        #expect(text.contains("No second question"))
        #expect(!text.localizedCaseInsensitiveContains("no opinion"))
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

    @Test("continue aside makes one forward move and still answers their question")
    func continueAsideFloorHand() {
        let aside = ConversationCueAssembler.continueAside
        #expect(aside.contains("at most three sentences"))
        #expect(aside.localizedCaseInsensitiveContains("when it sounds natural"))
        #expect(aside.localizedCaseInsensitiveContains("one forward move"))
        #expect(aside.localizedCaseInsensitiveContains("one hook"))
        #expect(aside.localizedCaseInsensitiveContains("short hook"))
        #expect(aside.localizedCaseInsensitiveContains("one-word"))
        #expect(aside.localizedCaseInsensitiveContains("never a second question"))
        #expect(!aside.localizedCaseInsensitiveContains("likes or wants"))
        #expect(!aside.localizedCaseInsensitiveContains("only hand the floor"))
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
        #expect(prefix.localizedCaseInsensitiveContains("do not claim to be human"))
        #expect(prefix.localizedCaseInsensitiveContains("one sentence"))
        #expect(prefix.localizedCaseInsensitiveContains("only if they brought it up"))
        #expect(prefix.localizedCaseInsensitiveContains("background sound"))
        #expect(!prefix.localizedCaseInsensitiveContains("end with a question"))
        #expect(!prefix.localizedCaseInsensitiveContains("always ask"))
        #expect(!prefix.localizedCaseInsensitiveContains("always end"))
    }

    @Test("codeSwitch aside asks for English without naming their language")
    func codeSwitchAside() {
        let previous = ConversationLiveNudge.spokenCodeSwitchEnabled
        ConversationLiveNudge.spokenCodeSwitchEnabled = true
        defer { ConversationLiveNudge.spokenCodeSwitchEnabled = previous }

        #expect(ConversationCueAssembler.v1MaySend(.codeSwitch))
        let text = ConversationCueAssembler.instructions(
            prefix: "PREFIX",
            stance: "STANCE",
            cue: .codeSwitch
        )
        #expect(text.contains("PREFIX"))
        #expect(text.localizedCaseInsensitiveContains("english"))
        #expect(text.localizedCaseInsensitiveContains("messy"))
        #expect(!text.localizedCaseInsensitiveContains("spanish"))
        #expect(ConversationCueAssembler.heard(.codeSwitch, in: "Try that last bit in English — messy is ok."))
    }
}
