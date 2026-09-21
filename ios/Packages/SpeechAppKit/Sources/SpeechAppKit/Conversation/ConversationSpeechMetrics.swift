import Foundation

/// A user-speech interval from fixture timestamps or recorded VAD ranges.
/// Live SpeechAnalyzer `audioTimeRange` is the intended source; v1 kit uses
/// recorded start/end times after hang-up, never on the `response.create` path.
public struct ConversationSpeechInterval: Equatable, Sendable {
    public let start: TimeInterval
    public let end: TimeInterval

    public init(start: TimeInterval, end: TimeInterval) {
        self.start = start
        self.end = end
    }

    public var duration: TimeInterval { max(0, end - start) }
}

/// Time spoken = union of speech ranges. Coverage of claimed speech below 0.7
/// is `limitedAnalysis` (report as uncertain). Does not start a mic source.
public struct ConversationSpeechMetrics: Equatable, Sendable {
    public static let coverageFloor: Double = 0.7

    public let spokenSeconds: TimeInterval
    public let coverage: Double
    public let limitedAnalysis: Bool

    public static func from(
        ranges: [ConversationSpeechInterval],
        claimedSpeechSeconds: TimeInterval
    ) -> ConversationSpeechMetrics {
        let spoken = unionDuration(ranges)
        let coverage: Double
        if claimedSpeechSeconds > 0 {
            coverage = spoken / claimedSpeechSeconds
        } else {
            coverage = spoken == 0 ? 1 : 0
        }
        return ConversationSpeechMetrics(
            spokenSeconds: spoken,
            coverage: coverage,
            limitedAnalysis: coverage < coverageFloor
        )
    }

    public static func unionDuration(_ ranges: [ConversationSpeechInterval]) -> TimeInterval {
        let merged = merged(ranges)
        return merged.reduce(0) { $0 + $1.duration }
    }

    public static func merged(_ ranges: [ConversationSpeechInterval]) -> [ConversationSpeechInterval] {
        let valid = ranges
            .filter { $0.end > $0.start }
            .sorted { $0.start < $1.start }
        guard var current = valid.first else { return [] }
        var out: [ConversationSpeechInterval] = []
        for next in valid.dropFirst() {
            if next.start <= current.end {
                current = ConversationSpeechInterval(
                    start: current.start,
                    end: max(current.end, next.end)
                )
            } else {
                out.append(current)
                current = next
            }
        }
        out.append(current)
        return out
    }
}
