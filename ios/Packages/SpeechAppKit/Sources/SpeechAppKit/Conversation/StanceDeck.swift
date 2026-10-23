import Foundation

public struct StanceCard: Sendable {
    public let views: [String]
}

public struct StanceDeck: Sendable {
    public let cards: [ConversationCard]
    public var views: [String] { cards.flatMap(\.views) }
    public enum BankError: Error { case missing }

    public static func loadBundled() throws -> StanceDeck {
        let bank = try OpenPromptBank.loadBundled()
        guard !bank.cards.isEmpty else { throw BankError.missing }
        return StanceDeck(cards: bank.cards)
    }

    /// Every view from one card. A single borrowed opinion from another topic is not a person.
    public func sample(rng: inout SplitMix64) -> StanceCard {
        let card = cards[Int(rng.next() % UInt64(cards.count))]
        return StanceCard(views: card.views)
    }
}

public struct SplitMix64: RandomNumberGenerator, Sendable {
    private var state: UInt64
    public init(seed: UInt64) { state = seed }
    public mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
