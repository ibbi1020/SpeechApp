import Testing
@testable import SpeechAppKit

@Suite("Monologue prompt cursor")
struct MonologuePromptCursorTests {
    @Test("last prompt is reopened when it still exists")
    func reopenLast() {
        var cursor = MonologuePromptCursor(
            prompts: ["alpha", "bravo", "charlie"],
            lastPrompt: "bravo"
        )
        #expect(cursor.current == "bravo")
        cursor.skip()
        #expect(cursor.current == "charlie")
        cursor.skip()
        #expect(cursor.current == "alpha")
    }

    @Test("missing last prompt starts at the first item")
    func missingLast() {
        let cursor = MonologuePromptCursor(
            prompts: ["alpha", "bravo"],
            lastPrompt: "ghost"
        )
        #expect(cursor.current == "alpha")
    }

    @Test("bundled opens are a valid familiar bank")
    func bundled() throws {
        let bank = try OpenPromptBank.loadBundled()
        let cursor = MonologuePromptCursor(prompts: bank.prompts, lastPrompt: nil)
        #expect(!cursor.current.isEmpty)
        #expect(!cursor.current.lowercased().contains("suicide"))
    }
}
