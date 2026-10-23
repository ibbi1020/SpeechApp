import Testing
@testable import SpeechAppKit

@Suite("Open prompts and stances")
struct OpenPromptBankTests {
    @Test("loads at least 20 non-trauma preference opens")
    func twentyOpens() throws {
        let bank = try OpenPromptBank.loadBundled()
        #expect(bank.prompts.count >= 20)
        #expect(bank.prompts.allSatisfy { $0.contains("?") })
        #expect(!bank.prompts.contains { $0.localizedCaseInsensitiveContains("what kind do you forget") })
        expectNoBannedThemes(
            bank.prompts,
            ["suicide", "war", "politic", "trauma", "wage", "despair", "news", "surveillance"]
        )
    }

    @Test("a sampled card keeps its question and all of its views together")
    func cardStaysTogether() throws {
        var rng = SplitMix64(seed: 1)
        let bank = try OpenPromptBank.loadBundled()
        let deck = try StanceDeck.loadBundled()
        #expect(deck.views.count >= 12)
        let card = bank.sample(rng: &rng)
        #expect(card.views.count >= 4)
        #expect(bank.cards.contains { $0 == card })
        let stance = deck.sample(rng: &rng)
        #expect(bank.cards.contains { $0.views == stance.views })
        #expect(stance.views.count >= 4)
    }
}
