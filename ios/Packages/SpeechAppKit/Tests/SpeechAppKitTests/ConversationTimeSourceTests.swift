import Testing
@testable import SpeechAppKit

@Suite("Conversation time source")
struct ConversationTimeSourceTests {
    @Test("controllable clock advances only when we say so")
    func controllable() {
        let time = ControllableTimeSource(now: 0)
        #expect(time.now == 0)
        time.advance(90)
        #expect(time.now == 90)
    }
}
