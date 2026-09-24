import Testing
@testable import SpeechAppKit

@Suite("Monologue token overlap")
struct MonologueOverlapTests {
    @Test("identical wording is 100")
    func identical() {
        let percent = MonologueOverlap.tokenPercent(
            previous: "I take the bus to work",
            current: "I take the bus to work"
        )
        #expect(percent == 100)
    }

    @Test("disjoint wording is 0")
    func disjoint() {
        let percent = MonologueOverlap.tokenPercent(
            previous: "cats sleep",
            current: "dogs run"
        )
        #expect(percent == 0)
    }

    @Test("partial overlap is Jaccard on unique tokens")
    func partial() {
        // {a,b} vs {b,c} → 1/3
        let percent = MonologueOverlap.tokenPercent(previous: "a b", current: "b c")
        #expect(percent == 100.0 / 3.0)
    }

    @Test("empty pair is nil")
    func empty() {
        #expect(MonologueOverlap.tokenPercent(previous: "  ", current: "") == nil)
    }
}
