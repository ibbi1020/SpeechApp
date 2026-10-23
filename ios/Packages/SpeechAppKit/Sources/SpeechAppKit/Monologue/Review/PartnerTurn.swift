import Foundation

/// Conversation: when the partner was speaking, on the saved recording's timeline,
/// and what they said. Lets the player show the question above the answer.
public struct PartnerTurn: Codable, Equatable, Hashable, Sendable {
    public let text: String
    public let start: TimeInterval
    public let end: TimeInterval
    /// Word times for listen-back. Missing on recordings saved before partner words.
    public let words: [RecordedWord]?

    public init(
        text: String,
        start: TimeInterval,
        end: TimeInterval,
        words: [RecordedWord]? = nil
    ) {
        self.text = text
        self.start = start
        self.end = end
        self.words = words
    }
}
