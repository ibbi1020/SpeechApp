import Foundation

/// Sum of gaps ≥250 ms between merged user-speech ranges.
/// A scalar only: no clause bounds and no hesitation location.
public enum ConversationPauseTime {
    public static let minimumGap: TimeInterval = 0.25

    /// `excluding` is partner playback on the same clock as `ranges`.
    /// Only the silence left in each gap counts. A gap that is only the partner adds nothing.
    public static func seconds(
        from ranges: [ConversationSpeechInterval],
        excluding occupied: [ConversationSpeechInterval] = [],
        minimumGap: TimeInterval = minimumGap
    ) -> TimeInterval {
        let merged = ConversationSpeechMetrics.merged(ranges)
        guard merged.count >= 2 else { return 0 }
        let blocked = ConversationSpeechMetrics.merged(occupied)
        var total: TimeInterval = 0
        for index in 1..<merged.count {
            let gapStart = merged[index - 1].end
            let gapEnd = merged[index].start
            let silence = (gapEnd - gapStart) - overlap(from: gapStart, to: gapEnd, blocked: blocked)
            if silence >= minimumGap {
                total += silence
            }
        }
        return total
    }

    /// How much of `[start, end)` is covered by already-merged blocks.
    private static func overlap(
        from start: TimeInterval,
        to end: TimeInterval,
        blocked: [ConversationSpeechInterval]
    ) -> TimeInterval {
        var covered: TimeInterval = 0
        for block in blocked {
            let lower = max(start, block.start)
            let upper = min(end, block.end)
            if upper > lower {
                covered += upper - lower
            }
        }
        return covered
    }

    public static func count(
        from ranges: [ConversationSpeechInterval],
        minimumGap: TimeInterval = minimumGap
    ) -> Int {
        let merged = ConversationSpeechMetrics.merged(ranges)
        guard merged.count >= 2 else { return 0 }
        var total = 0
        for index in 1..<merged.count {
            let gap = merged[index].start - merged[index - 1].end
            if gap >= minimumGap {
                total += 1
            }
        }
        return total
    }
}
