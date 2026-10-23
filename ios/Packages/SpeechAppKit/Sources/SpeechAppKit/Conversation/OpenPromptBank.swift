import Foundation

public struct ConversationCard: Codable, Sendable, Equatable {
    public let question: String
    public let views: [String]
}

public struct OpenPromptBank: Sendable {
    public let cards: [ConversationCard]
    public var prompts: [String] { cards.map(\.question) }
    public enum BankError: Error { case missing }

    public static func loadBundled() throws -> OpenPromptBank {
        guard let url = Bundle.module.url(
            forResource: "cards", withExtension: "json", subdirectory: "Conversation"
        ) ?? Bundle.module.url(forResource: "cards", withExtension: "json")
        else { throw BankError.missing }
        let cards = try JSONDecoder().decode([ConversationCard].self, from: Data(contentsOf: url))
        return OpenPromptBank(cards: cards)
    }

    /// One card: the question and the views that belong to it. Views are not mixed across cards.
    public func sample(rng: inout SplitMix64) -> ConversationCard {
        cards[Int(rng.next() % UInt64(cards.count))]
    }
}
