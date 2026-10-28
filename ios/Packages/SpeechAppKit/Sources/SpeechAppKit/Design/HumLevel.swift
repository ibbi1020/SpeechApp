import Foundation

/// Microphone loudness for the hum field.
///
/// The played tone leaks into the mic. The picture takes off a small fixed
/// amount, not a level it learns. A learned floor treats a held hum as leak
/// and, a few seconds in, pulls the field back to rest. Taking five percent
/// of the tone off does the same thing immediately, because that percent is
/// as loud as the hum.
public struct HumLevel: Equatable, Sendable {
    /// Share of the tone's RMS that a phone mic hears while the speaker plays.
    /// Conversation uses this to ignore the partner's voice. The hum picture
    /// does not: five percent of this tone is as loud as a hum.
    public static let speakerLeak: Double = 0.05

    /// Most the hum picture will treat as speaker bleed.
    ///
    /// The played tone sits near full scale. Five percent of that is about
    /// 0.03, and 0.03 is the raised voice the field is built to show. Taking
    /// the whole five percent off left a hum at rest. Speech is louder, so
    /// speech still moved the dots.
    public static let pictureLeak: Double = 0.003

    /// Smoothed level, 0...1. Silence stays near 0.
    public private(set) var smoothed: Double = 0

    /// RMS of the tone currently playing. 0 before it starts and after it ends.
    public var playbackRMS: Double = 0

    public init() {}

    /// One microphone buffer. `micRMS` is the raw buffer loudness, 0...1.
    @discardableResult
    public mutating func observe(micRMS: Double) -> Double {
        let fullLeak = max(0, playbackRMS) * Self.speakerLeak
        let leaked = min(fullLeak, Self.pictureLeak)
        let heard = max(0, micRMS - leaked)
        let raw = DitherHorizon.voiceLevel(rms: heard)
        let follow = raw > smoothed ? 0.55 : 0.16
        smoothed += (raw - smoothed) * follow
        return smoothed
    }

    public mutating func reset() {
        smoothed = 0
        playbackRMS = 0
    }
}
