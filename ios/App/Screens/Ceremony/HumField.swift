import SpeechAppKit
import SwiftUI

/// The dithered horizon behind the hum step. Amber circles, centred below the
/// bottom edge. Silence leaves a thin band; the user's voice lifts it.
/// Breathing does not use this. That step keeps its ring.
struct HumField: View {
    var voice: Double
    /// The hum step keeps the amber. The room warning passes green, yellow, or orange.
    var ink: Color = Self.amber

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Evening palette from the prototype. Morning is the cool alternative there;
    /// the ceremony ships the warm one.
    static let amber = Color(red: 1, green: 196.0 / 255, blue: 128.0 / 255)

    /// Holds each dot's opacity between frames. A class so a redraw can continue
    /// a fade that started on the previous one.
    @State private var presence = DotPresence()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            Canvas { context, size in
                presence.draw(
                    into: &context,
                    size: size,
                    date: timeline.date,
                    voice: voice,
                    reduceMotion: reduceMotion,
                    ink: ink
                )
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Per-dot opacity. A dot that crosses the threshold eases in, and one that
/// drops out eases away, over about a tenth of a second. Long enough to stop
/// the pop, short enough that the field still feels like it is following the voice.
private final class DotPresence {
    private struct Cell {
        var opacity: Float = 0
        var side: Float = 0
    }

    /// How long a dot takes to arrive or leave.
    private static let fade: TimeInterval = 0.10

    private var cells: [Cell] = []
    private var columns = 0
    private var lastDate: Date?

    func draw(
        into context: inout GraphicsContext,
        size: CGSize,
        date: Date,
        voice: Double,
        reduceMotion: Bool,
        ink: Color
    ) {
        let dt = elapsed(until: date)
        let level = DitherHorizon.level(voice: voice, reduceMotion: reduceMotion)
        let cell = DitherHorizon.cell(forWidth: size.width)
        let field = DitherHorizon.field(size: size, level: level, gain: DitherHorizon.humGain)
        let columnCount = Int(ceil(size.width / cell))
        let rowCount = Int(ceil(size.height / cell))
        guard columnCount > 0, rowCount > 0 else { return }
        fit(columns: columnCount, rows: rowCount)

        // Five steps is enough at this speed. A continuous alpha per dot would
        // be a separate draw for every circle.
        var bands = [Path(), Path(), Path(), Path(), Path()]
        let step = Float(min(dt / Self.fade, 1))

        for row in 0 ..< rowCount {
            for column in 0 ..< columnCount {
                let index = row * columnCount + column
                let side = DitherHorizon.dotSide(
                    column: column,
                    row: row,
                    cell: cell,
                    field: field
                )
                var dot = cells[index]
                if reduceMotion {
                    dot.opacity = side > 0 ? 1 : 0
                    dot.side = Float(side)
                } else if side > 0 {
                    dot.opacity = min(1, dot.opacity + step)
                    dot.side = Float(side)
                } else {
                    dot.opacity = max(0, dot.opacity - step)
                }
                cells[index] = dot
                guard dot.opacity > 0.05, dot.side > 0 else { continue }
                let band = min(4, Int(dot.opacity * 5))
                let x = CGFloat(column) * cell + cell / 2
                let y = CGFloat(row) * cell + cell / 2
                let drawn = CGFloat(dot.side)
                bands[band].addEllipse(in: CGRect(
                    x: x - drawn / 2,
                    y: y - drawn / 2,
                    width: drawn,
                    height: drawn
                ))
            }
        }

        for band in 0 ..< bands.count where bands[band].isEmpty == false {
            let opacity = Double(band + 1) / Double(bands.count)
            context.fill(bands[band], with: .color(ink.opacity(opacity)))
        }
    }

    private func elapsed(until date: Date) -> TimeInterval {
        let dt = lastDate.map { date.timeIntervalSince($0) } ?? 0
        lastDate = date
        return min(max(dt, 0), 0.05)
    }

    private func fit(columns: Int, rows: Int) {
        let count = columns * rows
        guard columns != self.columns || cells.count != count else { return }
        self.columns = columns
        cells = Array(repeating: Cell(), count: count)
    }
}
