import SpeechAppKit
import SwiftUI

/// Keeps each disc's swirl going across the shove, which recreates the discs.
final class ExerciseGasClock {
    private var flow: Double = 0
    private var last: TimeInterval?

    func sample(at date: Date, speed: Double, frozen: Bool) -> Double {
        if frozen { return ExerciseOrbField.stillTime }
        let now = date.timeIntervalSinceReferenceDate
        if let last {
            let dt = min(0.05, max(0, now - last))
            flow += dt * speed
        }
        last = now
        return flow
    }
}

/// Swirling gas for one exercise disc.
struct ExerciseGasDisc: View {
    var field: ExerciseOrbField
    var clock: ExerciseGasClock
    var reduceMotion: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: reduceMotion)) { timeline in
            let time = clock.sample(
                at: timeline.date,
                speed: field.speed,
                frozen: reduceMotion
            ) + field.phase
            GeometryReader { geo in
                Rectangle()
                    .colorEffect(shader(size: geo.size, time: time))
            }
        }
        .accessibilityHidden(true)
    }

    private func shader(size: CGSize, time: Double) -> Shader {
        let gases = field.gases
        return ShaderLibrary.exerciseGas(
            .float2(Float(size.width), Float(size.height)),
            .float(Float(time)),
            .float(Float(field.activity)),
            .float(Float(field.gray)),
            .color(swatch(gases.plate)),
            .color(swatch(gases.secondary))
        )
    }

    private func swatch(_ stop: ExerciseOrbField.Stop) -> Color {
        Color(red: stop.red, green: stop.green, blue: stop.blue)
    }
}
