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

    @Test("bundled monologue bank is experiential with Talk about / Describe stems")
    func bundled() throws {
        let bank = try MonologuePromptBank.loadBundled()
        #expect(bank.prompts.count >= 20)
        let cursor = MonologuePromptCursor(prompts: bank.prompts, lastPrompt: nil)
        #expect(!cursor.current.isEmpty)
        #expect(bank.prompts.allSatisfy { prompt in
            prompt.hasPrefix("Talk about") || prompt.hasPrefix("Describe")
        })
        expectNoBannedThemes(
            bank.prompts,
            ["suicide", "politic", "news", "trauma", "surveillance", "cancel culture"]
        )
    }
}
