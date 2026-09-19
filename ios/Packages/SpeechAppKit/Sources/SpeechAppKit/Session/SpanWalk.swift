import Foundation

/// Live place-marker at sentence/clause grain — at most one span ahead of occupancy.
public struct SpanWalkState: Equatable, Sendable {
    public var currentSpanIndex: Int
    public var spanProgress: Double
    /// Span the fill clock is timing against.
    public var fillSpanIndex: Int?
    public var speechStartedAt: TimeInterval?

    public init(
        currentSpanIndex: Int = 0,
        spanProgress: Double = 0,
        fillSpanIndex: Int? = nil,
        speechStartedAt: TimeInterval? = nil
    ) {
        self.currentSpanIndex = max(0, currentSpanIndex)
        self.spanProgress = spanProgress
        self.fillSpanIndex = fillSpanIndex
        self.speechStartedAt = speechStartedAt
    }
}

public enum SpanWalkEvent: Equatable, Sendable {
    case advanced(from: Int, to: Int)
    case snapped(to: Int)
}

/// Pure span-walk clock — testable without audio / ASR.
public enum SpanWalk {
    /// Live highlight may lead occupancy by at most this many spans.
    public static let maxSpansAhead = 1
    public static let silenceDecay: Double = 0.08

    public static func syllableDuration(syllableCount: Int) -> TimeInterval {
        max(0.35, Double(max(1, syllableCount)) * 0.22)
    }

    /// Mic tick: fill current span; when full and still speaking, advance (capped at one ahead of occupancy).
    public static func tick(
        state: SpanWalkState,
        speaking: Bool,
        now: TimeInterval,
        spanCount: Int,
        syllableCounts: [Int: Int],
        occupancySpanIndex: Int?
    ) -> (SpanWalkState, SpanWalkEvent?) {
        guard spanCount > 0 else { return (state, nil) }
        var next = state
        next.currentSpanIndex = min(next.currentSpanIndex, spanCount - 1)

        if speaking {
            return tickWhileSpeaking(
                state: next,
                now: now,
                spanCount: spanCount,
                syllableCounts: syllableCounts,
                occupancySpanIndex: occupancySpanIndex
            )
        }
        return (decayFillOnSilence(next), nil)
    }

    /// When occupancy moves into a later span, snap the live index forward (never rewind).
    public static func reconcile(
        state: SpanWalkState,
        occupancySpanIndex: Int?,
        speaking: Bool,
        now: TimeInterval
    ) -> (SpanWalkState, SpanWalkEvent?) {
        guard let occupancySpanIndex else { return (state, nil) }
        guard occupancySpanIndex > state.currentSpanIndex else {
            return (state, nil)
        }
        var next = state
        next.currentSpanIndex = occupancySpanIndex
        next.spanProgress = 0
        next.fillSpanIndex = occupancySpanIndex
        next.speechStartedAt = speaking ? now : nil
        return (next, .snapped(to: occupancySpanIndex))
    }

    /// Spans already behind the live highlight that occupancy has at least reached.
    public static func passedSpanIndices(
        currentSpanIndex: Int,
        occupancySpanIndex: Int?,
        spanCount: Int
    ) -> [Int] {
        guard spanCount > 0 else { return [] }
        let occ = occupancySpanIndex ?? -1
        let lastPassed = min(currentSpanIndex - 1, occ)
        guard lastPassed >= 0 else { return [] }
        return Array(0...lastPassed)
    }

    // MARK: - Private

    private static func tickWhileSpeaking(
        state: SpanWalkState,
        now: TimeInterval,
        spanCount: Int,
        syllableCounts: [Int: Int],
        occupancySpanIndex: Int?
    ) -> (SpanWalkState, SpanWalkEvent?) {
        var next = state
        let spanIndex = next.currentSpanIndex

        if next.fillSpanIndex != spanIndex || next.speechStartedAt == nil {
            next.fillSpanIndex = spanIndex
            next.speechStartedAt = now
        }

        let syllables = syllableCounts[spanIndex] ?? 1
        let duration = syllableDuration(syllableCount: syllables)
        let elapsed = now - (next.speechStartedAt ?? now)
        next.spanProgress = min(1, elapsed / duration)

        guard next.spanProgress >= 1 else {
            return (next, nil)
        }

        let occ = occupancySpanIndex ?? 0
        let canAdvance =
            (spanIndex - occ) < maxSpansAhead
            && spanIndex + 1 < spanCount

        guard canAdvance else {
            next.spanProgress = 1
            return (next, nil)
        }

        let from = spanIndex
        let to = spanIndex + 1
        next.currentSpanIndex = to
        next.spanProgress = 0
        next.fillSpanIndex = to
        next.speechStartedAt = now
        return (next, .advanced(from: from, to: to))
    }

    private static func decayFillOnSilence(_ state: SpanWalkState) -> SpanWalkState {
        guard state.spanProgress > 0 else { return state }
        var next = state
        next.spanProgress = max(0, next.spanProgress - silenceDecay)
        if next.spanProgress == 0 {
            next.speechStartedAt = nil
        }
        return next
    }
}
