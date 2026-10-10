import Foundation

/// Conversation: when the partner was speaking, on the saved recording's timeline,
/// and what they said. Lets the player show the question above the answer.
public struct PartnerTurn: Codable, Equatable, Hashable, Sendable {
    public let text: String
    public let start: TimeInterval
    public let end: TimeInterval

    public init(text: String, start: TimeInterval, end: TimeInterval) {
        self.text = text
        self.start = start
        self.end = end
    }
}
