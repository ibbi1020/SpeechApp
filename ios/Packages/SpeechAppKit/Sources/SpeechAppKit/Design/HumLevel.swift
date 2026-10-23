import Foundation

/// Microphone loudness for the hum field.
///
/// The played tone leaks into the mic. That leak is a fixed fraction of the
/// tone, not a level the meter learns. A learned floor treats a held hum as
/// leak and, a few seconds in, pulls the field back to rest.
public struct HumLevel: Equatable, Sendable {
    /// Share of the tone's RMS that a phone mic hears while the speaker plays.
    public static let speakerLeak: Double = 0.05

    /// Smoothed level, 0...1. Silence stays near 0.
    public private(set) var smoothed: Double = 0

    /// RMS of the tone currently playing. 0 before it starts and after it ends.
    public var playbackRMS: Double = 0

    public init() {}

    /// One microphone buffer. `micRMS` is the raw buffer loudness, 0...1.
    @discardableResult
    public mutating func observe(micRMS: Double) -> Double {
        let leaked = max(0, playbackRMS) * Self.speakerLeak
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
