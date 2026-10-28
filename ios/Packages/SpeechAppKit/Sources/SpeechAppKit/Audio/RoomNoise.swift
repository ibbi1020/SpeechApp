import Foundation

/// How loud the room is, in decibels relative to full scale.
///
/// The phone meter is not a calibrated sound-level meter. A quiet room on the
/// measurement tap sits near −40 dBFS. The ceremony uses that scale.
public enum RoomNoise {
    /// Ignore this long after the microphone opens. Starting the session pops.
    public static let settle: Double = 0.4
    /// How much sound one reading averages.
    public static let window: Double = 1
    /// At or above this, a quiet room becomes a warning.
    public static let warn: Double = -36
    /// A warning ends only once the room is this quiet. Two decibels below `warn`.
    public static let clear: Double = -38
    /// Yellow holds through here. Above it, the field warms toward orange.
    public static let warm: Double = -24
    /// Fully orange at this level and above.
    public static let hot: Double = -12

    /// `20 * log10(rms)`. Silence is a finite floor, still green.
    public static func decibels(rms: Double) -> Double {
        let level = max(0, rms)
        guard level > 0 else { return -160 }
        return 20 * log10(level)
    }

    /// Color from the live level. The button does not use this. It has hysteresis.
    public static func band(decibels: Double) -> Band {
        if decibels < warn { return .green }
        if decibels <= warm { return .yellow }
        let span = hot - warm
        let mix = min(1, (decibels - warm) / span)
        return .orange(mix)
    }

    /// Whether the button should say the room is still too loud.
    ///
    /// Entering the warning takes −36. Leaving it takes −38, so a reading that
    /// sits on the line does not flip the label back and forth.
    public static func warning(decibels: Double, wasWarning: Bool) -> Bool {
        if wasWarning {
            return decibels > clear
        }
        return decibels >= warn
    }

    /// What the warning screen should say. A meter that just opened has no verdict,
    /// so it must not replace a warning already on screen with "quieter now."
    public static func shownWarning(held: Bool, ready: Bool, reading: Bool) -> Bool {
        guard ready else { return held }
        return reading
    }

    public enum Band: Equatable, Sendable {
        case green
        case yellow
        /// 0 is yellow. 1 is orange.
        case orange(Double)
    }
}

/// A running room reading. Nothing is a verdict until the pop has passed and a
/// full second has been averaged. After that, the level is the latest second.
public struct RoomReading: Sendable {
    public private(set) var ready = false
    public private(set) var decibels: Double?
    public private(set) var warning = false

    private var samples: [(time: Double, rms: Double)] = []

    public init() {}

    /// `seconds` is time since the microphone opened. Samples during the settle
    /// are dropped, so a start-up pop cannot warn on its own.
    public mutating func observe(rms: Double, at seconds: Double) {
        let level = max(0, rms)
        if seconds >= RoomNoise.settle {
            samples.append((seconds, level))
        }
        guard seconds >= RoomNoise.settle + RoomNoise.window else { return }
        let windowStart = seconds - RoomNoise.window
        samples.removeAll { $0.time < windowStart }
        guard samples.isEmpty == false else { return }
        var power = 0.0
        for sample in samples {
            power += sample.rms * sample.rms
        }
        let mean = (power / Double(samples.count)).squareRoot()
        let measured = RoomNoise.decibels(rms: mean)
        decibels = measured
        ready = true
        warning = RoomNoise.warning(decibels: measured, wasWarning: warning)
    }
}
