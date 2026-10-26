import Testing
@testable import SpeechAppKit

@Suite("Speech rest")
struct SpeechRestTests {
    @Test("quiet before any speech does not offer Done")
    func silenceBeforeSpeech() {
        var rest = SpeechRest()
        rest.note(speaking: false, at: 5)
        #expect(rest.offersDone == false)
    }

    @Test("speech clears Done")
    func speechClears() {
        var rest = SpeechRest()
        rest.note(speaking: true, at: 1)
        rest.note(speaking: false, at: 1 + SpeechRest.quietSeconds)
        rest.note(speaking: true, at: 10)
        #expect(rest.offersDone == false)
    }

    @Test("three seconds of quiet after speech offers Done")
    func quietOffersDone() {
        var rest = SpeechRest()
        rest.note(speaking: true, at: 1)
        rest.note(speaking: false, at: 1 + SpeechRest.quietSeconds - 0.01)
        #expect(rest.offersDone == false)
        rest.note(speaking: false, at: 1 + SpeechRest.quietSeconds)
        #expect(rest.offersDone == true)
    }

    @Test("a pause restarts the quiet wait")
    func holdRestartsWait() {
        var rest = SpeechRest()
        rest.note(speaking: true, at: 1)
        rest.note(speaking: false, at: 2)
        rest.hold(at: 20)
        rest.note(speaking: false, at: 20 + SpeechRest.quietSeconds - 0.01)
        #expect(rest.offersDone == false)
        rest.note(speaking: false, at: 20 + SpeechRest.quietSeconds)
        #expect(rest.offersDone == true)
    }
}
