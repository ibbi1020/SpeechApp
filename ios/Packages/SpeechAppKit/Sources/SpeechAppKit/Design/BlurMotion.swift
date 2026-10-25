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

/// The pause wash on an exercise.
///
/// The wash climbs from the bottom and stops at `reach` of the screen. Above that
/// the exercise is only blurred. The gray is deliberate: a black wash reads as a
/// scrim, and the word under the icon is gray rather than white so the icon stays
/// the brightest thing on the screen.
public enum PauseVeilMotion {
    /// How far up the screen the wash climbs, measured from the bottom.
    public static let reach: CGFloat = 0.75
    /// Blur and the climb share this duration. The pause mark waits until it ends.
    /// The two together take a third of a second.
    public static let veil: TimeInterval = 0.24
    /// Fade of the icon and the word, after the veil has settled.
    public static let mark: TimeInterval = 0.09
    /// A light defocus. A tenth of the modal backdrop, so the exercise stays present.
    public static let blurRadius: CGFloat = 2.8
    /// Width of the rising edge, as a fraction of the wash. Wide so the edge is a
    /// fade the whole way up, not a hard line with a gradient only at the end.
    public static let feather: CGFloat = 0.7

    /// Wash pigment, `#0e0e0e`. Dark gray, not black.
    public static let washWhite: CGFloat = CGFloat(0x0E) / 255
    /// Opacity of that gray at the bottom edge.
    public static let washOpacity: Double = 0.94
    /// Stronger bottom when Reduce Transparency has removed the blur.
    public static let opaqueWashOpacity: Double = 0.98
    /// The word under the icon. Below one so it stays gray, not white.
    public static let labelWhite: CGFloat = 0.66

    /// One stop on the wash, from the top of the risen veil (clear) to the bottom.
    public struct Stop: Equatable, Sendable {
        public var location: CGFloat
        public var opacity: Double

        public init(location: CGFloat, opacity: Double) {
            self.location = location
            self.opacity = opacity
        }
    }

    /// Opacity down the wash. It keeps changing from the clear top to the bottom.
    /// A plateau partway down reads as a solid slab with a fade glued to its edge.
    public static func stops(bottomOpacity: Double) -> [Stop] {
        [
            Stop(location: 0, opacity: 0),
            Stop(location: 0.25, opacity: bottomOpacity * 0.22),
            Stop(location: 0.5, opacity: bottomOpacity * 0.48),
            Stop(location: 0.75, opacity: bottomOpacity * 0.74),
            Stop(location: 1, opacity: bottomOpacity),
        ]
    }

    /// How much of the full wash to show at `t` (0 = top of the wash, 1 = bottom)
    /// while `progress` moves from 0 to 1. The bottom leads. The feather stays wide
    /// at every progress, so the rising edge is a gradient rather than a cut.
    public static func reveal(at t: CGFloat, progress: CGFloat) -> Double {
        let clampedT = min(1, max(0, t))
        let clampedP = min(1, max(0, progress))
        let fromBottom = 1 - clampedT
        let leading = clampedP * (1 + feather) - feather
        let shown = (leading + feather - fromBottom) / feather
        return Double(min(1, max(0, shown)))
    }

    /// Samples of `reveal` from the top of the wash to the bottom.
    public static func revealStops(progress: CGFloat) -> [Stop] {
        let locations: [CGFloat] = [0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1]
        return locations.map { Stop(location: $0, opacity: reveal(at: $0, progress: progress)) }
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
