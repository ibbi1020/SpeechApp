import SpeechAppKit
import SwiftUI

/// The wash behind the exercise step. One plate per exercise. Changing the
/// choice dissolves through blur, then the new plate resolves. The scrim above
/// it does not dissolve: it is what keeps the headline on black.
struct ExerciseField: View {
    var kind: PracticeFormat.Kind

    var body: some View {
        BlurDissolve(value: kind, radius: BlurMotion.dissolveRadius) { shown in
            ExercisePlateCanvas(kind: shown)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Holds the heading on black while the plate lives in the lower half.
struct ExerciseScrim: View {
    var body: some View {
        LinearGradient(
            stops: [
                .init(color: .black.opacity(0.72), location: 0),
                .init(color: .black.opacity(0.15), location: 0.38),
                .init(color: .clear, location: 0.62),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Black, then a soft wash of the plate colour.
private struct ExercisePlateCanvas: View {
    var kind: PracticeFormat.Kind

    var body: some View {
        Canvas { context, size in
            let plate = ExercisePlate.plate(for: kind)
            let ink = Color(red: plate.red, green: plate.green, blue: plate.blue)
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
            for glow in plate.glows {
                let center = CGPoint(x: glow.x * size.width, y: glow.y * size.height)
                let radius = glow.radius * size.height
                let peak = 0.55 * glow.peak
                context.fill(
                    Path(CGRect(origin: .zero, size: size)),
                    with: .radialGradient(
                        Gradient(stops: [
                            .init(color: ink.opacity(peak), location: 0),
                            .init(color: ink.opacity(peak * 0.28), location: 0.45),
                            .init(color: .clear, location: 1),
                        ]),
                        center: center,
                        startRadius: 0,
                        endRadius: radius
                    )
                )
            }
        }
    }
}
