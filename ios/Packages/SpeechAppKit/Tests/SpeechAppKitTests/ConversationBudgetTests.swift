import Testing
@testable import SpeechAppKit

@Suite("Conversation budget")
struct ConversationBudgetTests {
    @Test("start disabled at zero")
    func disabled() {
        let b = ConversationBudgetSnapshot(limit: 20, used: 20, month: "2026-09")
        #expect(b.startEnabled == false)
        #expect(b.label == "20 of 20")
    }

    @Test("used 3 shows 3 of 20")
    func label() {
        let b = ConversationBudgetSnapshot(limit: 20, used: 3, month: "2026-09")
        #expect(b.startEnabled == true)
        #expect(b.label == "3 of 20")
    }
}
