import Foundation

/// Whether breath and hum run before the next exercise.
///
/// A sitting opens when a ceremony finishes. For the next half hour, Begin
/// goes to the exercise without grounding again. A later exercise does not
/// move that half hour. If an exercise is still going when the half hour
/// ends, the one exercise that starts within ten minutes of that ending is
/// still part of the sitting. After that, the next Begin grounds them again.
public struct PracticeSitting: Equatable, Sendable {
    public var startedAt: Date?
    public var exerciseStartedAt: Date?
    public var exerciseEndedAt: Date?

    /// How long a finished ceremony covers.
    public static let window: TimeInterval = 30 * 60
    /// How long after a straddling exercise the next one still skips grounding.
    public static let carry: TimeInterval = 10 * 60

    public init(
        startedAt: Date? = nil,
        exerciseStartedAt: Date? = nil,
        exerciseEndedAt: Date? = nil
    ) {
        self.startedAt = startedAt
        self.exerciseStartedAt = exerciseStartedAt
        self.exerciseEndedAt = exerciseEndedAt
    }

    /// A ceremony just finished. The clock starts here, and it does not restart
    /// when another exercise in this sitting begins.
    public func opened(at now: Date) -> PracticeSitting {
        PracticeSitting(startedAt: now)
    }

    public func startedExercise(at now: Date) -> PracticeSitting {
        var copy = self
        copy.exerciseStartedAt = now
        copy.exerciseEndedAt = nil
        return copy
    }

    /// The first end sticks. Leaving a report, or home, must not move it later.
    public func endedExercise(at now: Date) -> PracticeSitting {
        guard let exerciseStartedAt else { return self }
        if let exerciseEndedAt, exerciseEndedAt >= exerciseStartedAt { return self }
        var copy = self
        copy.exerciseEndedAt = now
        return copy
    }

    /// True when breath and hum should run.
    public func needsGrounding(at now: Date) -> Bool {
        guard let startedAt else { return true }
        let expiry = startedAt.addingTimeInterval(Self.window)
        if now < expiry { return false }
        // Still inside an exercise when the half hour ended, and that exercise
        // has since finished. The next start has ten minutes from that finish.
        guard let exerciseStartedAt, exerciseStartedAt < expiry else { return true }
        guard let exerciseEndedAt, exerciseEndedAt >= expiry else { return true }
        return now >= exerciseEndedAt.addingTimeInterval(Self.carry)
    }
}
