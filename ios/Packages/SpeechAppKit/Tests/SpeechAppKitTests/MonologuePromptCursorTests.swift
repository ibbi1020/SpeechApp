import Testing
@testable import SpeechAppKit

@Suite("Monologue prompt cursor")
struct MonologuePromptCursorTests {
    @Test("opening skips the topic from last time")
    func skipsSavedTopic() {
        var hits = Set<String>()
        for seed in UInt64(1)...40 {
            var rng = SplitMix64(seed: seed)
            let cursor = MonologuePromptCursor(
                prompts: ["alpha", "bravo", "charlie"],
                lastPrompt: "bravo",
                rng: &rng
            )
            #expect(cursor.current != "bravo")
            hits.insert(cursor.current)
        }
        #expect(hits == ["alpha", "charlie"])
    }

    @Test("a missing last prompt is not stuck on the first topic")
    func missingLastIsNotFirst() {
        var hits = Set<String>()
        for seed in UInt64(1)...40 {
            var rng = SplitMix64(seed: seed)
            let cursor = MonologuePromptCursor(
                prompts: ["alpha", "bravo", "charlie"],
                lastPrompt: nil,
                rng: &rng
            )
            hits.insert(cursor.current)
        }
        #expect(hits.count > 1)
        #expect(hits.contains("alpha"))
    }

    @Test("change topic picks a different prompt")
    func skipPicksAnother() {
        var rng = SplitMix64(seed: 7)
        var cursor = MonologuePromptCursor(
            prompts: ["alpha", "bravo", "charlie"],
            lastPrompt: nil,
            rng: &rng
        )
        let first = cursor.current
        cursor.skip(using: &rng)
        #expect(cursor.current != first)
        #expect(["alpha", "bravo", "charlie"].contains(cursor.current))
    }

    @Test("bundled monologue bank is experiential with Talk about / Describe stems")
    func bundled() throws {
        let bank = try MonologuePromptBank.loadBundled()
        #expect(bank.prompts.count >= 20)
        var rng = SplitMix64(seed: 1)
        let cursor = MonologuePromptCursor(prompts: bank.prompts, lastPrompt: nil, rng: &rng)
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
