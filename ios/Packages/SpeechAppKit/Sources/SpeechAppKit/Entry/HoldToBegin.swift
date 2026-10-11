import Foundation

/// Press-and-hold on Home. The hold is the only ceremony before a session, so the
/// view owns the gesture and this owns the arithmetic.
public struct HoldToBegin: Equatable, Sendable {
    public static let defaultDuration: TimeInterval = 1.25

    public let duration: TimeInterval

    public init(duration: TimeInterval = HoldToBegin.defaultDuration) {
        self.duration = duration
    }

    /// 0…1 for how much of the hold is done. A non-positive duration is already finished.
    public func fraction(elapsed: TimeInterval) -> Double {
        guard duration > 0 else { return 1 }
        return min(1, max(0, elapsed / duration))
    }

    public func isComplete(elapsed: TimeInterval) -> Bool {
        fraction(elapsed: elapsed) >= 1
    }
}
