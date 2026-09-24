import Foundation

public struct MonologueTake: Equatable, Sendable {
    public static let countingWall: TimeInterval = 30

    public let index: Int
    public let wallSeconds: TimeInterval
    public let ranges: [ConversationSpeechInterval]
    public let transcript: String

    public init(
        index: Int,
        wallSeconds: TimeInterval,
        ranges: [ConversationSpeechInterval],
        transcript: String
    ) {
        self.index = index
        self.wallSeconds = wallSeconds
        self.ranges = ranges
        self.transcript = transcript
    }

    public var counts: Bool { wallSeconds >= Self.countingWall }

    public var spokenSeconds: TimeInterval {
        ConversationSpeechMetrics.unionDuration(ranges)
    }
}
