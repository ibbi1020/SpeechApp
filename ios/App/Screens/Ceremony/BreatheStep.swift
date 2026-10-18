import SpeechAppKit
import SwiftUI

/// Paced breathing at six breaths a minute, four seconds in and six out, three times.
///
/// The circle is the pacer: it grows for the whole inhale and shrinks for the whole
/// exhale, so nobody has to read a number to know where they are. It stays off screen
/// through "Get ready", then resolves in with the first inhale, because arriving on
/// a ring already mid-breath means missing the first one.
struct BreatheStep: View {
    @Binding var fill: CGFloat
    /// Hidden through "Get ready". The ring resolves in with the first "Breathe in".
    @Binding var showCircle: Bool
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
        var hidden = Transaction()
        hidden.disablesAnimations = true
        withTransaction(hidden) { showCircle = false }
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
        if showCircle == false {
            withAnimation(SpeechBlur.motion(reduceMotion: reduceMotion)) {
                showCircle = true
            }
        }
        if reduceMotion == false {
            withAnimation(.easeInOut(duration: seconds)) { fill = target }
        }
        try? await Task.sleep(for: .seconds(seconds))
    }
}

/// The pacer: an open white ring, no fill. Centred on the bottom edge of the display,
/// so what shows is its upper half, and sized against the screen rather than a box.
/// At a full inhale the circle is taller than the screen, so the crown sits well up
/// into the empty space under the instruction instead of hugging the button.
struct BreathCircle: View {
    var fill: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// What is on screen while a leg is not running. `fill` itself jumps to the
    /// target as soon as the leg starts, so the ring cannot read it mid-breath.
    @State private var shownFill: CGFloat = 0
    @State private var wakeSign: CGFloat = 1
    @State private var wakeStart: Date?
    @State private var wakeDuration: Double = BreathPacing.inhale

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
            // The wake and the ring share one clock. Dividing the smear by a scale
            // the compositor is still easing would slide it off the stroke.
            TimelineView(.animation(minimumInterval: 1 / 60, paused: wakeStart == nil)) { context in
                let sample = BreathWakeMath.sample(
                    start: wakeStart,
                    duration: wakeDuration,
                    date: context.date,
                    sign: wakeSign,
                    resting: shownFill
                )
                let scale = max(restShare + (1 - restShare) * sample.fill, 0.01)
                ZStack {
                    // The even halo is weight, not a trail. The line is solid white.
                    ring(width: 6.25, color: .white.opacity(0.26), blur: 6, scale: scale)
                    BreathWake(amount: sample.amount, sign: wakeSign, scale: scale)
                    ring(width: 3.5, color: .white, blur: 0, scale: scale)
                }
                .scaleEffect(scale)
                .transaction { $0.disablesAnimations = true }
                .frame(width: diameter, height: diameter)
                .position(x: proxy.size.width / 2, y: proxy.size.height)
                .onChange(of: context.date) { _, date in
                    guard let wakeStart, date.timeIntervalSince(wakeStart) >= wakeDuration else { return }
                    shownFill = wakeSign > 0 ? 1 : 0
                    self.wakeStart = nil
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: fill) { previous, next in
            guard next != previous else { return }
            guard reduceMotion == false else {
                shownFill = next
                wakeStart = nil
                return
            }
            wakeSign = next > previous ? 1 : -1
            wakeDuration = next > previous ? BreathPacing.inhale : BreathPacing.exhale
            wakeStart = Date()
        }
    }

    private func ring(width: CGFloat, color: Color, blur: CGFloat, scale: CGFloat) -> some View {
        Circle()
            .strokeBorder(color, lineWidth: width / scale)
            .blur(radius: blur / scale)
    }
}

/// Copies of the stroke, shifted opposite the motion and faded out.
/// Growing (crown rising) shifts down. Shrinking shifts up.
private struct BreathWake: View {
    var amount: CGFloat
    var sign: CGFloat
    var scale: CGFloat

    private let steps = 8

    var body: some View {
        // About 30% shorter and dimmer than the first phone pass. The smear
        // read too heavy on a small screen at the prototype's full strength.
        let length = 8.4 + 11.2 * amount
        ZStack {
            ForEach(1...steps, id: \.self) { step in
                let t = CGFloat(step) / CGFloat(steps)
                let fade = CGFloat(pow(Double(1 - t), 1.25))
                let dy = sign * length * t
                let alpha = 0.294 * fade * amount
                let blur = 1.1 + 5.5 * t
                Circle()
                    .strokeBorder(Color.white.opacity(Double(alpha)), lineWidth: 3.4 / scale)
                    .blur(radius: blur / scale)
                    .offset(y: dy / scale)
            }
        }
    }
}

private enum BreathWakeMath {
    struct Sample {
        var fill: CGFloat
        var amount: CGFloat
    }

    /// `fill` eases the way SwiftUI's ease-in-out does. `amount` is 0 at both
    /// ends of the leg and 1 at the midpoint, which is when the smear is strongest.
    static func sample(
        start: Date?,
        duration: Double,
        date: Date,
        sign: CGFloat,
        resting: CGFloat
    ) -> Sample {
        guard let start, duration > 0 else { return Sample(fill: resting, amount: 0) }
        let t = date.timeIntervalSince(start) / duration
        if t <= 0 { return Sample(fill: sign > 0 ? 0 : 1, amount: 0) }
        if t >= 1 { return Sample(fill: sign > 0 ? 1 : 0, amount: 0) }
        let eased = easeInOut(t)
        let fill = sign > 0 ? eased : 1 - eased
        return Sample(fill: CGFloat(fill), amount: CGFloat(4 * t * (1 - t)))
    }

    /// cubic-bezier(0.42, 0, 0.58, 1), the curve behind SwiftUI's ease-in-out.
    private static func easeInOut(_ x: Double) -> Double {
        let target = min(1, max(0, x))
        var u = target
        for _ in 0 ..< 6 {
            let estimate = cubic(u, 0, 0.42, 0.58, 1)
            let slope = cubicSlope(u, 0, 0.42, 0.58, 1)
            if abs(slope) < 0.000_001 { break }
            u = min(1, max(0, u - (estimate - target) / slope))
        }
        return cubic(u, 0, 0, 1, 1)
    }

    private static func cubic(_ u: Double, _ p0: Double, _ p1: Double, _ p2: Double, _ p3: Double) -> Double {
        let c = 1 - u
        return c * c * c * p0 + 3 * c * c * u * p1 + 3 * c * u * u * p2 + u * u * u * p3
    }

    private static func cubicSlope(_ u: Double, _ p0: Double, _ p1: Double, _ p2: Double, _ p3: Double) -> Double {
        let c = 1 - u
        return 3 * c * c * (p1 - p0) + 6 * c * u * (p2 - p1) + 3 * u * u * (p3 - p2)
    }
}
