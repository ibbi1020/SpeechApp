import CoreGraphics
import Foundation

/// First-open Home entrance. Greeting and Begin fade together. Both sheets
/// slide up from one line just off the bottom, and Gallery lands first.
/// Numbers match prototypes/home-entrance.
public enum HomeEntrance {
    public struct Curve: Equatable, Sendable {
        public var x1: Double
        public var y1: Double
        public var x2: Double
        public var y2: Double

        public init(x1: Double, y1: Double, x2: Double, y2: Double) {
            self.x1 = x1
            self.y1 = y1
            self.x2 = x2
            self.y2 = y2
        }
    }

    /// Greeting and Begin. CSS cubic-bezier(0.23, 1, 0.32, 1).
    public static let fadeDuration: TimeInterval = 0.48
    public static let fadeCurve = Curve(x1: 0.23, y1: 1, x2: 0.32, y2: 1)

    /// Gallery card. CSS ease-out, cubic-bezier(0, 0, 0.58, 1).
    public static let galleryDuration: TimeInterval = 0.184

    /// Progress card. Same curve, longer travel, so it is still moving when Gallery is home.
    public static let progressDuration: TimeInterval = 0.284
    public static let slideCurve = Curve(x1: 0, y1: 0, x2: 0.58, y2: 1)

    /// All three start together.
    public static let startDelay: TimeInterval = 0

    /// How far past the bottom edge the card tops start, so they share one line.
    public static let startPastEdge: CGFloat = 32

    public static func travel(cardHeight: CGFloat) -> CGFloat {
        cardHeight + startPastEdge
    }
}
