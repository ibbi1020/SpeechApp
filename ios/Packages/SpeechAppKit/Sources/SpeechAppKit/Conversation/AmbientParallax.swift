import Foundation

/// How far a place picture slides when the phone tilts.
///
/// The pose is the fused accelerometer and gyroscope (roll, pitch, yaw).
/// The first pose is the center, so a normal hold starts still.
/// Tilting toward an edge reveals the cropped edge on that side.
public enum AmbientParallax {
    public struct Pose: Equatable, Sendable {
        public var roll: Double
        public var pitch: Double
        public var yaw: Double

        public init(roll: Double, pitch: Double, yaw: Double) {
            self.roll = roll
            self.pitch = pitch
            self.yaw = yaw
        }
    }

    public struct Shift: Equatable, Sendable {
        public var x: Double
        public var y: Double
        public var degrees: Double

        public static let centered = Shift(x: 0, y: 0, degrees: 0)

        public init(x: Double, y: Double, degrees: Double) {
            self.x = x
            self.y = y
            self.degrees = degrees
        }
    }

    /// Radians of tilt that reach the full slide.
    public static let tiltSpan: Double = 0.35
    /// Furthest slide, in points.
    public static let maxSlide: Double = 16
    /// Furthest twist, in degrees.
    public static let maxTwist: Double = 1.2

    /// Slide from the pose where the picture was centered.
    public static func shift(from reference: Pose, to current: Pose) -> Shift {
        let roll = unit((current.roll - reference.roll) / tiltSpan)
        let pitch = unit((current.pitch - reference.pitch) / tiltSpan)
        let yaw = unit((current.yaw - reference.yaw) / tiltSpan)
        return Shift(
            x: -roll * maxSlide,
            y: -pitch * maxSlide,
            degrees: yaw * maxTwist
        )
    }

    /// Ease toward the latest tilt so a shaky hand does not shimmer the picture.
    public static func smooth(previous: Shift, target: Shift, factor: Double = 0.12) -> Shift {
        let keep = 1 - factor
        return Shift(
            x: previous.x * keep + target.x * factor,
            y: previous.y * keep + target.y * factor,
            degrees: previous.degrees * keep + target.degrees * factor
        )
    }

    /// Extra scale on top of a fill, so the furthest slide still hides the screen edge.
    ///
    /// Filling the screen already crops the loose side of the picture. The extra
    /// scale only has to cover the side that is flush, plus the twist.
    public static func zoom(
        viewWidth: Double,
        viewHeight: Double,
        imageWidth: Double,
        imageHeight: Double
    ) -> Double {
        guard viewWidth > 0, viewHeight > 0, imageWidth > 0, imageHeight > 0 else { return 1 }
        let twist = maxTwist * .pi / 180
        let horizontalNeed = maxSlide + (viewHeight / 2) * sin(twist)
        let verticalNeed = maxSlide + (viewWidth / 2) * sin(twist)
        let imageAspect = imageWidth / imageHeight
        let viewAspect = viewWidth / viewHeight
        let fillWidth: Double
        let fillHeight: Double
        if imageAspect > viewAspect {
            fillHeight = viewHeight
            fillWidth = viewHeight * imageAspect
        } else {
            fillWidth = viewWidth
            fillHeight = viewWidth / imageAspect
        }
        // One point past the math, so a soft edge does not peek through.
        let pad = 1.0
        let zoomX = (viewWidth + 2 * (horizontalNeed + pad)) / fillWidth
        let zoomY = (viewHeight + 2 * (verticalNeed + pad)) / fillHeight
        return max(1, zoomX, zoomY)
    }

    private static func unit(_ value: Double) -> Double {
        min(1, max(-1, value))
    }
}
