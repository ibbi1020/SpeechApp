import Foundation

/// Sum of gaps ≥250 ms between merged user-speech ranges.
/// A scalar only: no clause bounds and no hesitation location.
public enum ConversationPauseTime {
    public static let minimumGap: TimeInterval = 0.25

    public static func seconds(
        from ranges: [ConversationSpeechInterval],
        minimumGap: TimeInterval = minimumGap
    ) -> TimeInterval {
        let merged = ConversationSpeechMetrics.merged(ranges)
        guard merged.count >= 2 else { return 0 }
        var total: TimeInterval = 0
        for index in 1..<merged.count {
            let gap = merged[index].start - merged[index - 1].end
            if gap >= minimumGap {
                total += gap
            }
        }
        return total
    }
}
