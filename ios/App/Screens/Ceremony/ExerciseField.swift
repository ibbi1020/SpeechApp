import SpeechAppKit
import SwiftUI

/// The dither behind the exercise step. One plate per exercise. Changing the
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

/// Black, a soft wash of the plate colour, then the Bayer dots.
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

            let cell = DitherHorizon.cell(forWidth: size.width)
            guard cell > 0 else { return }
            let sources = plate.sources(in: size)
            let columns = Int(ceil(size.width / cell))
            let rows = Int(ceil(size.height / cell))
            var dots = Path()
            for row in 0 ..< rows {
                for column in 0 ..< columns {
                    let side = DitherHorizon.dotSide(
                        column: column,
                        row: row,
                        cell: cell,
                        sources: sources
                    )
                    guard side > 0 else { continue }
                    let x = CGFloat(column) * cell + cell / 2
                    let y = CGFloat(row) * cell + cell / 2
                    dots.addEllipse(in: CGRect(
                        x: x - side / 2,
                        y: y - side / 2,
                        width: side,
                        height: side
                    ))
                }
            }
            context.fill(dots, with: .color(ink))
        }
    }
}
