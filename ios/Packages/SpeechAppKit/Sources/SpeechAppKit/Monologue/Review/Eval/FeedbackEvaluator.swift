import Foundation

/// Compares what the marker logic produced against hand or script labels.
///
/// Matching follows sound-event-detection practice (sed_eval): same kind, and the
/// onsets fall within a tolerance, or the two time spans overlap.
public struct FeedbackScore: Equatable, Sendable {
    public struct Match: Equatable, Sendable {
        public let label: FeedbackLabel
        public let marker: ReviewMarker
    }

    /// Expected moments the system found.
    public let matched: [Match]
    /// Expected moments the system did not find.
    public let missed: [FeedbackLabel]
    /// Moments flagged where nothing was expected (or where `expect: none` said not to).
    public let extra: [ReviewMarker]
    /// Flagged the right place but called it the wrong kind.
    public let wrongKind: [Match]

    public var precision: Double {
        let flagged = matched.count + extra.count + wrongKind.count
        return flagged == 0 ? 1 : Double(matched.count) / Double(flagged)
    }

    public var recall: Double {
        let expected = matched.count + missed.count
        return expected == 0 ? 1 : Double(matched.count) / Double(expected)
    }

    public var isPerfect: Bool {
        missed.isEmpty && extra.isEmpty && wrongKind.isEmpty
    }
}

public enum FeedbackEvaluator {
    /// Onset tolerance in seconds. Grok word times and planted silences rarely agree to the frame.
    public static let defaultTolerance: TimeInterval = 0.5

    /// Before the cap: did detection find every moment that should be found?
    public static func scoreCandidates(
        labels: [FeedbackLabel],
        candidates: [ReviewMarker],
        tolerance: TimeInterval = defaultTolerance
    ) -> FeedbackScore {
        score(
            required: labels.filter { $0.expect != .none },
            allowed: [],
            predicted: candidates,
            tolerance: tolerance
        )
    }

    /// After the cap: are the shown markers the ones a person would pick?
    /// `candidate` labels may be shown or hidden without penalty.
    public static func scoreMarkers(
        labels: [FeedbackLabel],
        markers: [ReviewMarker],
        tolerance: TimeInterval = defaultTolerance
    ) -> FeedbackScore {
        score(
            required: labels.filter { $0.expect == .marker },
            allowed: labels.filter { $0.expect == .candidate },
            predicted: markers,
            tolerance: tolerance
        )
    }

    static func hits(_ label: FeedbackLabel, _ marker: ReviewMarker, tolerance: TimeInterval) -> Bool {
        if abs(label.start - marker.start) <= tolerance { return true }
        return marker.start < label.end && label.start < marker.end
    }

    private static func score(
        required: [FeedbackLabel],
        allowed: [FeedbackLabel],
        predicted: [ReviewMarker],
        tolerance: TimeInterval
    ) -> FeedbackScore {
        // Closest-onset pairs first, so one marker never claims two labels.
        var pairs: [(label: Int, marker: Int, distance: Double)] = []
        for (li, label) in required.enumerated() {
            for (mi, marker) in predicted.enumerated() where marker.kind == label.kind {
                if hits(label, marker, tolerance: tolerance) {
                    pairs.append((li, mi, abs(label.start - marker.start)))
                }
            }
        }
        pairs.sort { $0.distance < $1.distance }

        var usedLabels = Set<Int>()
        var usedMarkers = Set<Int>()
        var matched: [FeedbackScore.Match] = []
        for pair in pairs where !usedLabels.contains(pair.label) && !usedMarkers.contains(pair.marker) {
            usedLabels.insert(pair.label)
            usedMarkers.insert(pair.marker)
            matched.append(.init(label: required[pair.label], marker: predicted[pair.marker]))
        }

        var wrongKind: [FeedbackScore.Match] = []
        var extra: [ReviewMarker] = []
        for (mi, marker) in predicted.enumerated() where !usedMarkers.contains(mi) {
            if allowed.contains(where: { $0.kind == marker.kind && hits($0, marker, tolerance: tolerance) }) {
                continue
            }
            if let li = required.indices.first(where: {
                !usedLabels.contains($0) && hits(required[$0], marker, tolerance: tolerance)
            }) {
                usedLabels.insert(li)
                wrongKind.append(.init(label: required[li], marker: marker))
                continue
            }
            extra.append(marker)
        }

        let missed = required.indices
            .filter { !usedLabels.contains($0) }
            .map { required[$0] }
        return FeedbackScore(
            matched: matched.sorted { $0.label.start < $1.label.start },
            missed: missed,
            extra: extra,
            wrongKind: wrongKind
        )
    }
}
