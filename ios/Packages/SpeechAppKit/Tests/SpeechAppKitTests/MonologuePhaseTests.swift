import Testing
@testable import SpeechAppKit

@Suite("Monologue phase and ceilings")
struct MonologuePhaseTests {
    @Test("ceilings are 4 then 3 then 2 minutes")
    func ceilings() {
        #expect(MonologueCeiling.seconds(forTake: 1) == 240)
        #expect(MonologueCeiling.seconds(forTake: 2) == 180)
        #expect(MonologueCeiling.seconds(forTake: 3) == 120)
    }

    @Test("a take counts at 30s wall")
    func countingFloor() {
        let short = MonologueTake(
            index: 1,
            wallSeconds: 8,
            ranges: [],
            transcript: "hi"
        )
        let long = MonologueTake(
            index: 1,
            wallSeconds: 30,
            ranges: [ConversationSpeechInterval(start: 0, end: 20)],
            transcript: "hello there"
        )
        #expect(short.counts == false)
        #expect(long.counts == true)
    }

    @Test("crisis is not a fluency end")
    func crisisEnd() {
        #expect(MonologueEndReason.crisisReferral.showsReport == false)
        #expect(MonologueEndReason.completed.showsReport == true)
        #expect(MonologueEndReason.leftEarly.showsReport == true)
    }
}
