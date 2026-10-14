import CoreGraphics
import Foundation

/// The ceremony's dithered horizon, ported from `prototypes/ceremony-background`.
///
/// One glow centred below the bottom edge, quantised to dots through an 8×8 Bayer
/// matrix. The hum step is the only ceremony step that draws it. Breathing keeps
/// its ring, because a breath needs a continuous edge to follow.
public enum DitherHorizon {
    /// Columns across the width. The prototype started at 112; fewer columns make
    /// each dot larger without changing the falloff.
    public static let columns: CGFloat = 64

    /// Hum step brightness, from the prototype's measured commitment arc.
    public static let humGain: Double = 0.88

    public struct Field: Equatable, Sendable {
        public var center: CGPoint
        public var radius: CGFloat
        /// Brightness at the middle of the glow, before the Bayer test.
        public var peak: Double
    }

    public static func cell(forWidth width: CGFloat) -> CGFloat {
        max(2, (width / columns).rounded())
    }

    /// Shared geometry with the prototype. `level` is 0...1 and sits on top of
    /// `gain`, so a resting field is still visible.
    public static func field(size: CGSize, level: Double, gain: Double) -> Field {
        let clamped = min(1, max(0, level))
        let rest = 0.46
        let span = 0.40
        let intensity = (0.34 + 0.66 * gain) * (0.62 + 0.38 * clamped)
        return Field(
            center: CGPoint(x: size.width / 2, y: size.height * 1.10),
            radius: size.height * (rest + span * clamped) * 0.78,
            peak: 1.05 * intensity
        )
    }

    /// Maps a microphone RMS to 0...1. Room noise sits near 0.01; a hum is well above.
    public static func voiceLevel(rms: Double) -> Double {
        min(1, max(0, (rms - 0.012) * 10))
    }

    /// How far the hum field is driven, 0...1.
    ///
    /// Quiet until the microphone rises. The field used to swell on a timer, which
    /// read as motion with nobody in it. Reduce Motion holds the floor still.
    /// A small floor keeps a few dots findable in silence; the voice does the rest.
    public static func level(voice: Double, reduceMotion: Bool) -> Double {
        let floor = 0.12
        if reduceMotion { return floor }
        return floor + (1 - floor) * min(1, max(0, voice))
    }

    /// Inverse-square brightness at a normalised distance from the glow's centre.
    ///
    /// `1 / (1 + 7r²)` thins the crown. The old `(1 - r)^2.1` curve held a flat
    /// band of similar dots across the top of the field.
    public static func brightness(distance: Double, peak: Double) -> Double {
        let d = min(1.15, max(0, distance))
        return peak / (1 + d * d * 7)
    }

    /// Side length of the dot whose cell is `column`, `row`, or 0 when that cell
    /// stays black. `cell` is the pitch from `cell(forWidth:)`.
    public static func dotSide(
        column: Int,
        row: Int,
        cell: CGFloat,
        field: Field
    ) -> CGFloat {
        guard field.radius > 0, cell > 0 else { return 0 }
        let x = CGFloat(column) * cell + cell / 2
        let y = CGFloat(row) * cell + cell / 2
        let distance = hypot(x - field.center.x, y - field.center.y) / field.radius
        guard distance < 1.15 else { return 0 }
        let value = brightness(distance: distance, peak: field.peak)
        // A small lift on the threshold drops the faintest scattered dots. The
        // core, where most cells clear it, stays dense.
        let threshold = bayer(column: column, row: row) * 0.85 + 0.07
        guard value > threshold else { return 0 }
        return cell * (0.62 + 0.38 * min(1, value))
    }

    /// Ordered 8×8 Bayer threshold, 0...1. Same matrix as the prototype.
    public static func bayer(column: Int, row: Int) -> Double {
        bayerTable[row & 7][column & 7]
    }

    private static let bayerTable: [[Double]] = [
        [0, 32, 8, 40, 2, 34, 10, 42],
        [48, 16, 56, 24, 50, 18, 58, 26],
        [12, 44, 4, 36, 14, 46, 6, 38],
        [60, 28, 52, 20, 62, 30, 54, 22],
        [3, 35, 11, 43, 1, 33, 9, 41],
        [51, 19, 59, 27, 49, 17, 57, 25],
        [15, 47, 7, 39, 13, 45, 5, 37],
        [63, 31, 55, 23, 61, 29, 53, 21],
    ].map { row in row.map { ($0 + 0.5) / 64 } }
}
