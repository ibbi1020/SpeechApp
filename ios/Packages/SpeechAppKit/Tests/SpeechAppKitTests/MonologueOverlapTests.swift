import Testing
@testable import SpeechAppKit

@Suite("Monologue verbatim reuse")
struct MonologueOverlapTests {
    @Test("identical wording is 100")
    func identical() {
        let percent = MonologueOverlap.verbatimPercent(
            previous: "I take the bus to work",
            current: "I take the bus to work"
        )
        #expect(percent == 100)
    }

    @Test("the same words in a new order are not a repeated stretch")
    func reordered() {
        let percent = MonologueOverlap.verbatimPercent(
            previous: "I went to the store",
            current: "the store I went to"
        )
        // Only "I went to" is still in order. Three of the five words.
        #expect(percent == 60)
    }

    @Test("a short pair cannot form a stretch")
    func tooShort() {
        #expect(MonologueOverlap.verbatimPercent(previous: "a b", current: "b c") == 0)
    }

    @Test("empty pair is nil")
    func empty() {
        #expect(MonologueOverlap.verbatimPercent(previous: "  ", current: "") == nil)
    }

    @Test("fillers do not change reuse")
    func fillersIgnored() {
        let without = MonologueOverlap.verbatimPercent(
            previous: "I went to the store",
            current: "I went to the store"
        )
        let with = MonologueOverlap.verbatimPercent(
            previous: "I um went uh to the store",
            current: "I went to the store"
        )
        #expect(without == with)
        #expect(without == 100)
    }
}
