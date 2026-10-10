import Foundation

/// Which exercise's marker rules a test case or clip runs through.
public enum FeedbackExercise: String, Codable, Equatable, Sendable {
    case monologue
    case reading
    case conversation
}

/// What the marker rules need beyond the timed words.
public struct FeedbackContext: Codable, Equatable, Sendable {
    public var exercise: FeedbackExercise
    /// Reading: the passage text the person was asked to read.
    public var passage: String?
    /// Conversation: when the partner was talking, on the recording's timeline.
    public var partnerTurns: [PartnerTurn]?

    public init(
        exercise: FeedbackExercise = .monologue,
        passage: String? = nil,
        partnerTurns: [PartnerTurn]? = nil
    ) {
        self.exercise = exercise
        self.passage = passage
        self.partnerTurns = partnerTurns
    }

    /// Every detected moment, then what the player would show after the cap.
    public func markers(
        words: [RecordedWord],
        durationSeconds: TimeInterval
    ) -> (candidates: [ReviewMarker], shown: [ReviewMarker]) {
        switch exercise {
        case .monologue:
            let found = ReviewMarkers.candidates(words: words, durationSeconds: durationSeconds)
            return (found, ReviewMarkers.select(found, durationSeconds: durationSeconds))
        case .conversation:
            let found = ConversationMarkers.candidates(
                words: words,
                partnerTurns: partnerTurns ?? [],
                durationSeconds: durationSeconds
            )
            return (found, ReviewMarkers.select(found, durationSeconds: durationSeconds))
        case .reading:
            let passage = Passage.plain(passage ?? "")
            let found = ReadingMarkers.candidates(passage: passage, words: words)
            return (found, ReviewMarkers.select(found, durationSeconds: durationSeconds))
        }
    }
}
