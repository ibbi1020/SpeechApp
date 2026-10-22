import Foundation

/// How long a person waits on the connecting orb before the model answers.
/// A refused connection does not use these limits. It fails as soon as it fails.
public enum ConnectionWaitPolicy {
    /// Shown above the orb once the wait has gone on long enough.
    public static let slowLine = "Taking a bit longer than expected…"

    /// The orb stays quiet until the connection has taken this long.
    public static let slowLineDelay: TimeInterval = 5

    /// A connection that never answers ends here.
    public static let hangLimit: TimeInterval = 10

    /// The slow line is up only inside the window between the two limits.
    public static func showsSlowLine(elapsed: TimeInterval) -> Bool {
        elapsed >= slowLineDelay && elapsed < hangLimit
    }

    /// The hang limit has been reached. The connecting orb should leave for the error.
    public static func hasHung(elapsed: TimeInterval) -> Bool {
        elapsed >= hangLimit
    }

    /// Seconds left before a hung connection should fail. Never negative.
    public static func remaining(since start: Date, now: Date) -> TimeInterval {
        max(0, hangLimit - now.timeIntervalSince(start))
    }
}
