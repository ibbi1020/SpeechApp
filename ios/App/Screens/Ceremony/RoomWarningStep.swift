import SpeechAppKit
import SwiftUI

/// The loud-room gate. Same field as the hum, recolored by the live level.
/// Copy follows the button, which waits two decibels before it calls the room quiet.
struct RoomWarningStep: View {
    var warning: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: SpeechSpacing.related) {
            BlurDissolve(line, size: CeremonyType.metrics(.display).size) { text in
                Text(text)
                    .ceremonyType(.display)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if warning {
                Text(CeremonyCopy.roomLoudDetail)
                    .ceremonyType(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(SpeechBlur.dissolve)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(SpeechMotion.swap, value: warning)
        .accessibilityElement(children: .combine)
    }

    private var line: String {
        warning ? CeremonyCopy.roomLoud : CeremonyCopy.roomClear
    }
}

/// Green, then yellow, then a slide toward orange. The mix comes from `RoomNoise`.
enum RoomInk {
    private static let green = (red: 0.35, green: 0.78, blue: 0.42)
    private static let yellow = (red: 0.98, green: 0.78, blue: 0.22)
    private static let orange = (red: 1.0, green: 0.42, blue: 0.12)

    static func color(decibels: Double) -> Color {
        switch RoomNoise.band(decibels: decibels) {
        case .green:
            return paint(green)
        case .yellow:
            return paint(yellow)
        case .orange(let mix):
            return paint(blend(yellow, orange, mix))
        }
    }

    private static func paint(_ ink: (red: Double, green: Double, blue: Double)) -> Color {
        Color(red: ink.red, green: ink.green, blue: ink.blue)
    }

    private static func blend(
        _ from: (red: Double, green: Double, blue: Double),
        _ to: (red: Double, green: Double, blue: Double),
        _ mix: Double
    ) -> (red: Double, green: Double, blue: Double) {
        let t = min(1, max(0, mix))
        return (
            red: from.red + (to.red - from.red) * t,
            green: from.green + (to.green - from.green) * t,
            blue: from.blue + (to.blue - from.blue) * t
        )
    }
}
