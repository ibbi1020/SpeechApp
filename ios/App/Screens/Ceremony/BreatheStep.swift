import SpeechAppKit
import SwiftUI

/// Paced breathing at six breaths a minute, four seconds in and six out, three times.
///
/// The circle is the pacer: it grows for the whole inhale and shrinks for the whole
/// exhale, so nobody has to read a number to know where they are. It holds still for
/// a few seconds first, because arriving on a screen already mid-breath means missing
/// the first one.
struct BreatheStep: View {
    @Binding var fill: CGFloat
    var onDone: (Bool) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: Phase = .settling

    private enum Phase: Equatable {
        case settling
        case inhale
        case exhale
        case finished
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SpeechSpacing.related) {
            // "Breathe in" and "Breathe out" are the same length and sit in the same
            // place, so a cross-fade between them is hard to read as a change at all.
            // Blurring out and back in reads as one word being replaced by another.
            BlurDissolve(instruction, size: CeremonyType.metrics(.display).size) { line in
                Text(line)
                    .ceremonyType(.display)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(CeremonyCopy.breatheLine)
                .ceremonyType(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
        .sensoryFeedback(.selection, trigger: phase)
        .task { await run() }
        .onDisappear { onDone(false) }
    }

    private var instruction: String {
        switch phase {
        case .settling: CeremonyCopy.breatheSettle
        case .inhale: CeremonyCopy.breatheIn
        case .exhale: CeremonyCopy.breatheOut
        case .finished: CeremonyCopy.breatheRate
        }
    }

    private func run() async {
        guard phase == .settling else { return }
        fill = 0
        try? await Task.sleep(for: .seconds(BreathPacing.settle))
        // Under Reduce Motion the circle holds at one steady size for the whole run.
        // Snapping it large and small every few seconds would be a slow oscillation,
        // which is the thing the setting exists to avoid. The instruction and the
        // haptic carry the pacing instead.
        if reduceMotion { fill = 0.5 }
        for _ in 0 ..< BreathPacing.cycles {
            await leg(.inhale, to: 1, seconds: BreathPacing.inhale)
            await leg(.exhale, to: 0, seconds: BreathPacing.exhale)
        }
        phase = .finished
        onDone(true)
    }

    private func leg(_ next: Phase, to target: CGFloat, seconds: Double) async {
        phase = next
        if reduceMotion == false {
            withAnimation(.easeInOut(duration: seconds)) { fill = target }
        }
        try? await Task.sleep(for: .seconds(seconds))
    }
}

/// The pacer: an open grey ring, no fill. Centred on the bottom edge of the display,
/// so what shows is its upper half, and sized against the screen rather than a box.
/// At a full inhale the circle is taller than the screen, so the crown sits well up
/// into the empty space under the instruction instead of hugging the button.
struct BreathCircle: View {
    var fill: CGFloat

    /// Diameter at a full inhale, as a share of screen height. Larger than the screen
    /// on purpose: the centre sits on the bottom edge, so only the upper half shows,
    /// and a circle that fits the screen leaves that arc too low.
    private let maxShare: CGFloat = 1.28
    /// Diameter at a full exhale, as a share of the above. Never down to nothing:
    /// the circle has to stay findable between breaths.
    private let restShare: CGFloat = 0.38

    var body: some View {
        GeometryReader { proxy in
            let diameter = proxy.size.height * maxShare
            let scale = max(restShare + (1 - restShare) * fill, 0.01)
            // Scale, not frame, so the swell stays on the compositor. Scaling also
            // multiplies every stroke and blur, which would leave the ring under a
            // point thick at a full exhale, so each is divided out first and lands at
            // the same rendered size whatever the circle is doing.
            ZStack {
                // Two passes: a close halo and the line itself. Enough to keep the
                // edge from looking cut out of the black, not enough to glow.
                ring(width: 2.5, white: 0.26, blur: 6, scale: scale)
                ring(width: 1.4, white: 0.52, blur: 0, scale: scale)
            }
            .scaleEffect(scale)
            .frame(width: diameter, height: diameter)
            .position(x: proxy.size.width / 2, y: proxy.size.height)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func ring(width: CGFloat, white: Double, blur: CGFloat, scale: CGFloat) -> some View {
        Circle()
            .strokeBorder(Color(white: white), lineWidth: width / scale)
            .blur(radius: blur / scale)
    }
}
