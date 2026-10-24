import CoreGraphics
import Foundation

/// One glow plate per exercise. The numbers are the magnetic-select prototype.
///
/// Reading is a cool horizon, centred and low, so the headline stays on black.
/// Monologue is a warmer glow set in from the left, climbing. Conversation is
/// one blue field on the right. It is not the mirror of the yellow one: that
/// glow sits in from the edge and climbs, this one is cropped by the right
/// edge, sits lower, and spreads wider.
public struct ExercisePlate: Equatable, Sendable {
    public struct Glow: Equatable, Sendable {
        /// Fraction of the width.
        public var x: Double
        /// Fraction of the height. Past 1 means the centre sits below the screen.
        public var y: Double
        /// Fraction of the height.
        public var radius: Double
        public var peak: Double
    }

    /// 0...1, matching the prototype's `rgb()` channels.
    public var red: Double
    public var green: Double
    public var blue: Double
    public var glows: [Glow]

    public static func plate(for kind: PracticeFormat.Kind) -> ExercisePlate {
        switch kind {
        case .reading:
            plate(236, 232, 224, Glow(x: 0.50, y: 1.06, radius: 0.48, peak: 0.92))
        case .monologue:
            plate(255, 206, 150, Glow(x: 0.30, y: 0.96, radius: 0.40, peak: 1.02))
        case .conversation:
            plate(186, 208, 232, Glow(x: 0.86, y: 1.08, radius: 0.52, peak: 0.94))
        }
    }

    public func sources(in size: CGSize) -> [DitherHorizon.Source] {
        glows.map { glow in
            DitherHorizon.Source(
                center: CGPoint(x: glow.x * size.width, y: glow.y * size.height),
                radius: glow.radius * size.height,
                peak: glow.peak
            )
        }
    }

    private static func plate(
        _ red: Double,
        _ green: Double,
        _ blue: Double,
        _ glow: Glow
    ) -> ExercisePlate {
        ExercisePlate(red: red / 255, green: green / 255, blue: blue / 255, glows: [glow])
    }
}
