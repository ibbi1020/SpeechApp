import Testing
@testable import SpeechAppKit

@Suite("Open prompts and stances")
struct OpenPromptBankTests {
    @Test("loads at least 20 non-trauma preference opens")
    func twentyOpens() throws {
        let bank = try OpenPromptBank.loadBundled()
        #expect(bank.prompts.count >= 20)
        #expect(bank.prompts.allSatisfy { $0.contains("?") })
        expectNoBannedThemes(
            bank.prompts,
            ["suicide", "war", "politic", "trauma", "wage", "despair", "news", "surveillance"]
        )
    }

    @Test("stance sample is 1 or 2 views")
    func stanceCount() throws {
        var rng = SplitMix64(seed: 1)
        let deck = try StanceDeck.loadBundled()
        #expect(deck.views.count >= 12)
        let card = deck.sample(rng: &rng)
        #expect((1...2).contains(card.views.count))
        let again = deck.sample(rng: &rng)
        #expect(!again.views.isEmpty)
        #expect((1...2).contains(again.views.count))
    }
}
