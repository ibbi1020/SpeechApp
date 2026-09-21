import Testing
@testable import SpeechAppKit

@Suite("Open prompts and stances")
struct OpenPromptBankTests {
    @Test("loads at least 20 non-trauma opens")
    func twentyOpens() throws {
        let bank = try OpenPromptBank.loadBundled()
        #expect(bank.prompts.count >= 20)
        #expect(bank.prompts.allSatisfy { !$0.lowercased().contains("suicide") })
        #expect(bank.prompts.allSatisfy { !$0.lowercased().contains("war") })
    }

    @Test("stance sample is 3 to 5 views")
    func stanceCount() throws {
        var rng = SplitMix64(seed: 1)
        let deck = try StanceDeck.loadBundled()
        let card = deck.sample(rng: &rng)
        #expect((3...5).contains(card.views.count))
        let again = try StanceDeck.loadBundled().sample(rng: &rng)
        // different seed path — just ensure non-empty
        #expect(!again.views.isEmpty)
    }
}
