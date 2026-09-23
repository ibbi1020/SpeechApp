import Foundation

/// Heightfield math for `AuroraPill`. Numbers match `docs/aurora-pill.md`.
enum AuroraPillMath {
    struct Peak: Sendable {
        var x: Double
        var amp: Double
    }

    struct Field: Sendable {
        var mode: AuroraPill.Mode
        var width: Double
        var rest: Double
        var lift: Double
    }

    struct RGBA: Sendable {
        var r: Double
        var g: Double
        var b: Double
        var a: Double
    }

    struct GradientStop: Sendable {
        var location: CGFloat
        var color: RGBA
    }

    static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
        a + (b - a) * min(1, max(0, t))
    }

    static func smoothstep(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double {
        let u = min(1, max(0, (x - edge0) / (edge1 - edge0)))
        return u * u * (3 - 2 * u)
    }

    static func wander(_ t: Double, _ a: Double, _ b: Double, _ c: Double, _ phase: Double) -> Double {
        0.5 + 0.5 * (
            0.48 * sin(t * a + phase) +
            0.32 * sin(t * b + phase * 1.73) +
            0.20 * sin(t * c + phase * 2.41)
        )
    }

    static func tDraw(raw t: Double, mode: AuroraPill.Mode) -> Double {
        switch mode {
        case .speak: t * 0.9
        case .listen: t * 0.5
        case .connect: t
        }
    }

    static func blurRadius(height: CGFloat, mode: AuroraPill.Mode) -> CGFloat {
        switch mode {
        case .speak: max(8, height * 0.16)
        case .listen: max(7, height * 0.13)
        case .connect: max(4, height * 0.05)
        }
    }

    static func field(energy e: Double, mode: AuroraPill.Mode) -> Field {
        switch mode {
        case .speak:
            // Broad overlapping hills — troughs stay blue, band fills lower half.
            Field(mode: mode, width: 0.22, rest: 0.74, lift: 0.38 + e * 0.22)
        case .connect:
            Field(mode: mode, width: 0.2, rest: 0.62, lift: 0)
        case .listen:
            Field(mode: mode, width: 0.18, rest: 0.60, lift: 0.05 + e * 0.40)
        }
    }

    static func peaks(tDraw t: Double, energy e: Double, mode: AuroraPill.Mode) -> [Peak] {
        switch mode {
        case .connect:
            return []
        case .speak:
            func speak(_ x0: Double, _ spread: Double, _ phase: Double) -> Peak {
                Peak(
                    x: x0 + spread * (wander(t, 1.9, 3.1, 4.7, phase) - 0.5),
                    amp: 0.08 + 1.12 * wander(t, 2.4, 3.8, 6.1, phase + 1.4)
                )
            }
            return [
                speak(0.22, 0.12, 0.3),
                speak(0.50, 0.10, 2.2),
                speak(0.78, 0.12, 4.1),
            ]
        case .listen:
            let liftL = wander(t, 0.41, 0.67, 1.13, 0.20)
            let liftR = wander(t, 0.29, 0.83, 1.01, 2.74)
            return [
                Peak(
                    x: 0.18 + 0.16 * wander(t, 0.33, 0.59, 0.97, 1.12),
                    amp: 0.36 + e * 0.10 + (0.18 + e * 0.58) * liftL
                ),
                Peak(
                    x: 0.64 + 0.16 * wander(t, 0.27, 0.71, 1.19, 3.41),
                    amp: 0.36 + e * 0.10 + (0.18 + e * 0.58) * liftR
                ),
            ]
        }
    }

    /// Ridge height as a fraction of pill height (`y` grows downward).
    static func ridgeY(
        xn: Double,
        t: Double,
        energy e: Double,
        peaks: [Peak],
        field: Field
    ) -> Double {
        // Connect is a traveling sine only — no peaks, no second harmonic.
        if field.mode == .connect {
            return field.rest - 0.08 * sin(xn * .pi * 4 - t * 1.6)
        }

        var lift = 0.0
        for peak in peaks {
            let d = xn - peak.x
            let mountain = exp(-(d * d) / (2 * field.width * field.width))
            lift += field.lift * mountain * peak.amp
        }

        let wave: Double
        switch field.mode {
        case .speak:
            // One shallow ripple. A second harmonic split the ice band into spikes.
            wave = 0.02 * sin(xn * .pi * 2.2 + t * 1.4)
        case .listen:
            wave = (0.018 * sin(xn * .pi * 2.05 + t * 0.62)
                + 0.010 * sin(xn * .pi * 4.6 - t * 1.05)) * (0.22 + e * 0.12)
        case .connect:
            wave = 0
        }
        return field.rest - lift + wave
    }

    /// Speak syllable stand-in on raw `t` when playback RMS is unavailable.
    static func speakEnergyTarget(raw t: Double) -> Double {
        let syllable = 0.5 + 0.5 * sin(t * 6.4)
        let phrase = 0.55 + 0.45 * sin(t * 1.9 + 0.4)
        return 0.42 + 0.5 * syllable * phrase
    }

    static func smoothEnergy(
        current: Double,
        target: Double,
        dt: Double,
        mode: AuroraPill.Mode
    ) -> Double {
        let clampedDT = min(0.05, max(0, dt))
        let rising = target > current
        let atkHz: Double
        switch mode {
        case .speak:
            atkHz = rising ? 7.5 : 3.4
        case .listen, .connect:
            atkHz = rising ? 4.2 : 2.0
        }
        return current + (target - current) * (1 - exp(-atkHz * clampedDT))
    }

    // MARK: Gradients

    private static func rgba(_ r: Double, _ g: Double, _ b: Double, _ a: Double) -> RGBA {
        RGBA(r: r, g: g, b: b, a: a)
    }

    private static func stop(_ location: CGFloat, _ color: RGBA) -> GradientStop {
        GradientStop(location: location, color: color)
    }

    private static func floorRGB(energy e: Double) -> (r: Double, g: Double, b: Double) {
        (lerp(130, 38, e), lerp(168, 96, e), lerp(228, 250, e))
    }

    /// Listen keeps the original cool-blue body. Speak is ice only.
    static func bodyStops(energy e: Double, mode: AuroraPill.Mode) -> [GradientStop] {
        if mode == .speak {
            return [
                stop(0, rgba(220, 240, 255, 0)),
                stop(0.12, rgba(220, 240, 255, 0.92)),
                stop(0.38, rgba(150, 200, 255, 1)),
                stop(1, rgba(40, 90, 200, 1)),
            ]
        }
        let floor = floorRGB(energy: e)
        let mid = rgba(lerp(100, 44, e), lerp(140, 108, e), lerp(214, 248, e), 1)
        let crestR = lerp(150, 70, e * 0.55)
        let crestG = lerp(186, 150, e * 0.45)
        let crestB = lerp(232, 255, e * 0.2)
        return [
            stop(0, rgba(crestR, crestG, crestB, 0)),
            stop(0.18, rgba(crestR, crestG, crestB, 0.85)),
            stop(0.42, mid),
            stop(1, rgba(floor.r, floor.g, floor.b, 1)),
        ]
    }

    static func shelfStops(energy e: Double) -> [GradientStop] {
        let floor = floorRGB(energy: e)
        return [
            stop(0, rgba(40, 80, 210, 0)),
            stop(0.35, rgba(40, 90, 230, 0.55)),
            stop(1, rgba(floor.r, floor.g, floor.b, 0.9)),
        ]
    }

    static func filamentStops(energy e: Double, mode: AuroraPill.Mode) -> [GradientStop] {
        if mode == .speak {
            return [
                stop(0, rgba(230, 245, 255, 0.42 + e * 0.12)),
                stop(0.14, rgba(180, 220, 255, 0.22)),
                stop(0.40, rgba(90, 150, 230, 0)),
                stop(1, rgba(0, 0, 0, 0)),
            ]
        }
        return [
            stop(0, rgba(160, 210, 255, 0.20 + e * 0.14)),
            stop(0.18, rgba(70, 140, 255, 0.14)),
            stop(0.45, rgba(20, 50, 160, 0)),
            stop(1, rgba(0, 0, 0, 0)),
        ]
    }

    /// Soft bloom above the ridge — ice-white fading to clear (all modes).
    static func glowStops() -> [GradientStop] {
        [
            stop(0, rgba(235, 248, 255, 0.55)),
            stop(0.22, rgba(200, 230, 255, 0.22)),
            stop(0.55, rgba(140, 190, 255, 0)),
            stop(1, rgba(0, 0, 0, 0)),
        ]
    }

    static func magentaStops(tall: Double) -> [GradientStop] {
        [
            stop(0, rgba(210, 90, 255, 0.55 * tall)),
            stop(0.35, rgba(80, 40, 180, 0.28 * tall)),
            stop(1, rgba(0, 0, 0, 0)),
        ]
    }

    static func greenStops(tall: Double) -> [GradientStop] {
        [
            stop(0, rgba(168, 236, 168, 0.82 * tall)),
            stop(0.22, rgba(96, 196, 120, 0.58 * tall)),
            stop(0.55, rgba(36, 110, 70, 0.12 * tall)),
            stop(1, rgba(0, 0, 0, 0)),
        ]
    }
}
