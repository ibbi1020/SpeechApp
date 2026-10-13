import CoreGraphics
import Foundation

/// Blur depths and durations measured frame by frame off FocusFlight's screen
/// recording, where blur does the job that sliding and scaling do elsewhere.
///
/// Three speeds came out of the measurement, and they are different jobs:
///
/// - A **dissolve** is content being replaced. The header went from sharp to gone
///   over 290ms on a smooth S-curve, reaching about 20pt of blur, with the fade
///   running slightly ahead of the blur.
/// - A **burst** is a control leaving. The confirm button hit 18pt within a single
///   frame and was down to a sixth of its opacity by 120ms. Far harder and faster
///   than a dissolve, because nothing is arriving in its place.
/// - A **backdrop** is content being pushed behind something else. The map blurred
///   to nothing in 250ms while a scrim took its mean brightness down to roughly a
///   third, and the arriving panel resolved sharp on top of it.
public enum BlurMotion {
    /// Blur a replaced surface passes through. Measured at the reference header.
    public static let dissolveRadius: CGFloat = 20
    /// Blur a departing control passes through. Harder, so the eye lets it go.
    public static let burstRadius: CGFloat = 30
    /// Blur applied to whatever sits behind a modal.
    public static let backdropRadius: CGFloat = 28

    /// One surface replacing another.
    public static let dissolve: TimeInterval = 0.28
    /// A control leaving with nothing taking its place.
    public static let burst: TimeInterval = 0.12
    /// Background settling behind a modal.
    public static let backdrop: TimeInterval = 0.30
    /// Reduce Motion has no blur ramp, so it gets a plain short fade instead.
    public static let reducedFade: TimeInterval = 0.2

    /// Scrim over a blurred backdrop. The blur alone does not darken — a Gaussian
    /// keeps the mean brightness — so the scrim carries the whole drop.
    public static let backdropDim: Double = 0.55
    /// Heavier scrim for Reduce Transparency, which gets no blur at all.
    public static let opaqueBackdropDim: Double = 0.72

    /// Below this, blur stops reading as "gone" and starts reading as "slightly
    /// smudged", which is worse than no blur.
    public static let minimumTextRadius: CGFloat = 6

    /// Blur that reads as gone for text of a given point size.
    ///
    /// Blur has to scale with the type or it lands wrong in both directions: 20pt of
    /// blur erases a caption into a bar of grey, and 6pt leaves a 51pt headline
    /// perfectly readable. The reference header is 51pt and dissolves through about
    /// 20pt, which is where four tenths comes from.
    public static func textRadius(forSize size: CGFloat) -> CGFloat {
        max(minimumTextRadius, size * 0.4)
    }
}

/// One end of a blur dissolve: how blurred a piece of content is and how opaque.
///
/// Both ends are the same type because entering and leaving are the same move in
/// opposite directions — content arrives out of blur exactly as it left into it.
public struct BlurPhase: Equatable, Sendable {
    public var radius: CGFloat
    public var opacity: Double

    public init(radius: CGFloat, opacity: Double) {
        self.radius = radius
        self.opacity = opacity
    }

    /// Settled: in focus and fully present.
    public static let sharp = BlurPhase(radius: 0, opacity: 1)

    /// Gone. Under Reduce Motion the blur is dropped and only the fade remains,
    /// because a blur ramp is the motion that setting exists to avoid.
    public static func dissolved(
        radius: CGFloat = BlurMotion.dissolveRadius,
        reduceMotion: Bool = false
    ) -> BlurPhase {
        BlurPhase(radius: reduceMotion ? 0 : radius, opacity: 0)
    }
}
