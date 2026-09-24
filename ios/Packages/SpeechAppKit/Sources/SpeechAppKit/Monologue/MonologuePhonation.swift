import Foundation

/// Speech time / take-clock wall time (Towell; De Jong).
/// Caller must pass wall that already excludes Pause / system-interrupt freeze.
public enum MonologuePhonation {
    public static func ratio(spoken: TimeInterval, wall: TimeInterval) -> Double? {
        guard wall > 0 else { return nil }
        return spoken / wall
    }
}
