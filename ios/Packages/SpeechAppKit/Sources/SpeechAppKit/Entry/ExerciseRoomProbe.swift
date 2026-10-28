import Foundation

/// What to do when the exercise-step room check finishes.
///
/// The check starts only after the user taps. It can outlive that tap: Back
/// leaves the ceremony without changing the exercise step, and a cancelled
/// check must not open the exercise.
public enum ExerciseRoomProbe {
    public enum Target: Equatable, Sendable {
        /// Walk on to the next ceremony step.
        case step
        /// This sitting is already open. Leave the ceremony and start.
        case start
    }

    public enum Outcome: Equatable, Sendable {
        case advance(Target)
        case warn
        /// Permission is off. The screen already has words for that.
        case denied
        /// The meter never became ready, and permission was not refused.
        case unavailable
        /// The user left, or the check was cancelled.
        case stay
    }

    public static func outcome(
        ready: Bool,
        denied: Bool,
        warning: Bool,
        cancelled: Bool,
        stillInExercise: Bool,
        target: Target
    ) -> Outcome {
        guard cancelled == false, stillInExercise else { return .stay }
        if denied { return .denied }
        guard ready else { return .unavailable }
        if warning { return .warn }
        return .advance(target)
    }
}
