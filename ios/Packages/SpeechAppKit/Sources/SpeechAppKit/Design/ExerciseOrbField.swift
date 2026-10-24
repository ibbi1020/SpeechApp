import Foundation

/// The gas inside an exercise disc.
///
/// The motion is the cloud orb's, turned down: a chosen disc churns, and the
/// others keep swirling more slowly and fade to gray. Reading is white and
/// grey. The other discs use two close hues of their plate colour.
public struct ExerciseOrbField: Equatable, Sendable {
    public struct Stop: Equatable, Sendable {
        public var red: Double
        public var green: Double
        public var blue: Double

        public init(red: Double, green: Double, blue: Double) {
            self.red = red
            self.green = green
            self.blue = blue
        }
    }

    /// The plate colour, and the same colour a short step around the hue wheel.
    public struct Gases: Equatable, Sendable {
        public var plate: Stop
        public var secondary: Stop
    }

    public var kind: PracticeFormat.Kind
    public var chosen: Bool
    public var hovered: Bool

    /// A developed swirl, used when motion is reduced.
    public static let stillTime: Double = 0.85

    public init(kind: PracticeFormat.Kind, chosen: Bool, hovered: Bool) {
        self.kind = kind
        self.chosen = chosen
        self.hovered = hovered
    }

    /// How fast the flow clock runs. Chosen is the speaking churn, reduced
    /// by 40%. The others stay in motion, just slower.
    public var speed: Double {
        if chosen { return 1.32 }
        if hovered { return 1.02 }
        return 0.78
    }

    /// How hard the gases twist. 40% under the speaking warp.
    public var activity: Double {
        if chosen { return 0.49 }
        if hovered { return 0.36 }
        return 0.28
    }

    /// 0 is full colour. The unchosen discs are pulled most of the way to gray.
    public var gray: Double {
        if chosen { return 0 }
        if hovered { return 0.42 }
        return 0.86
    }

    /// Keeps the three discs from swirling in step.
    public var phase: Double {
        switch kind {
        case .reading: 0
        case .monologue: 2.4
        case .conversation: 4.8
        }
    }

    public var gases: Gases {
        if kind == .reading {
            return Gases(
                plate: Stop(red: 1, green: 1, blue: 1),
                secondary: Stop(red: 0.68, green: 0.68, blue: 0.68)
            )
        }
        let plate = ExercisePlate.plate(for: kind)
        return Self.gases(from: Stop(red: plate.red, green: plate.green, blue: plate.blue))
    }

    /// `plate` is the exercise colour and stays exact. The other gas is
    /// about 22 degrees around the wheel and a clear step lighter or darker,
    /// still the same colour, just easier to tell apart.
    static func gases(from plate: Stop) -> Gases {
        let hsl = plate.hsl
        let lightness = hsl.l > 0.7 ? hsl.l - 0.11 : hsl.l + 0.11
        let secondary = Stop(
            hue: hsl.h + 0.06,
            saturation: min(1, hsl.s + 0.08),
            lightness: min(0.92, max(0.22, lightness))
        )
        return Gases(plate: plate, secondary: secondary)
    }
}

extension ExerciseOrbField.Stop {
    var hsl: (h: Double, s: Double, l: Double) {
        let maxValue = max(red, green, blue)
        let minValue = min(red, green, blue)
        let lightness = (maxValue + minValue) / 2
        let delta = maxValue - minValue
        guard delta > 1e-6 else { return (0, 0, lightness) }
        let saturation = delta / (1 - abs(2 * lightness - 1))
        let hue: Double
        if maxValue == red {
            hue = (green - blue) / delta + (green < blue ? 6 : 0)
        } else if maxValue == green {
            hue = (blue - red) / delta + 2
        } else {
            hue = (red - green) / delta + 4
        }
        return (hue / 6, saturation, lightness)
    }

    init(hue: Double, saturation: Double, lightness: Double) {
        let wrapped = hue - floor(hue)
        let chroma = saturation * min(lightness, 1 - lightness)
        func channel(_ n: Double) -> Double {
            let k = (n + wrapped * 12).truncatingRemainder(dividingBy: 12)
            let fold = max(-1, min(k - 3, min(9 - k, 1)))
            return lightness - chroma * fold
        }
        self.init(red: channel(0), green: channel(8), blue: channel(4))
    }
}
