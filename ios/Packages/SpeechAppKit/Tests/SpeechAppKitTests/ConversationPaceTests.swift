import Testing
@testable import SpeechAppKit

@Suite("Conversation pace")
struct ConversationPaceTests {
    @Test("vowel-nucleus heuristic yields raw syllables per minute")
    func knownString() {
        // "hello" = he-llo: nuclei e, o → 2 syllables. 2s of speech → 60 syl/min.
        let pace = ConversationPace.syllablesPerMinute(transcript: "hello", speechSeconds: 2)
        #expect(pace == 60)
    }

    @Test("zero speech seconds is not computable")
    func zeroSpeech() {
        #expect(ConversationPace.syllablesPerMinute(transcript: "hello", speechSeconds: 0) == nil)
    }

    @Test("empty transcript is not computable")
    func emptyTranscript() {
        #expect(ConversationPace.syllablesPerMinute(transcript: "   ", speechSeconds: 10) == nil)
    }
}
