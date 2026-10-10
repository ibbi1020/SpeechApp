import Foundation

/// One marker-rule test case, read from `eval/feedback/rules.json`.
public struct FeedbackRuleCase: Codable, Equatable, Sendable {
    public let name: String
    /// What the case protects, in plain words.
    public let why: String
    public let script: String
    /// Defaults to the script's own length. Set it to test the cap or spacing on a longer take.
    public let durationSeconds: TimeInterval?
    /// Text the first shown marker's note must contain.
    public let noteContains: String?
    /// Set when the case documents a gap the rules do not handle yet.
    public let knownIssue: String?

    public struct Result: Sendable {
        public let layout: FeedbackScript.Layout
        public let duration: TimeInterval
        public let candidates: FeedbackScore
        public let shown: FeedbackScore
        public let markers: [ReviewMarker]
        public let noteProblem: String?

        public var passed: Bool {
            candidates.isPerfect && shown.isPerfect && noteProblem == nil
        }
    }

    public func run(tolerance: TimeInterval = FeedbackEvaluator.defaultTolerance) throws -> Result {
        let layout = try FeedbackScript(script).layout()
        let duration = durationSeconds ?? layout.duration + 0.5
        let markers = ReviewMarkers.build(words: layout.words, durationSeconds: duration)
        let candidates = ReviewMarkers.candidates(words: layout.words, durationSeconds: duration)
        var noteProblem: String?
        if let noteContains {
            let notes = markers.map(\.note)
            if !notes.contains(where: { $0.contains(noteContains) }) {
                noteProblem = "No note contains “\(noteContains)”. Notes: \(notes)"
            }
        }
        return Result(
            layout: layout,
            duration: duration,
            candidates: FeedbackEvaluator.scoreCandidates(
                labels: layout.labels,
                candidates: candidates,
                tolerance: tolerance
            ),
            shown: FeedbackEvaluator.scoreMarkers(labels: layout.labels, markers: markers, tolerance: tolerance),
            markers: markers,
            noteProblem: noteProblem
        )
    }
}
