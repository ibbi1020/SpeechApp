import SwiftUI

/// Gemini Live–inspired aurora band: soft gradient ribbons that swell with mic energy.
/// Trust signal only — not word occupancy. Driven by `speechEnergy` (0…1 RMS).
struct AuroraPresenceView: View {
    var energy: Float
    var isLive: Bool
    var isHearingSpeech: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var samples: [CGFloat] = Array(repeating: Self.baseline, count: Self.sampleCount)
    @State private var smoothedEnergy: CGFloat = Self.baseline

    private static let sampleCount = 24
    private static let bandHeight: CGFloat = 64
    private static let baseline: CGFloat = 0.08
    private static let ribbonPointCount = 48

    private static let ribbons: [(phase: Double, amp: CGFloat, color: Color, line: CGFloat)] = [
        (0.0, 0.55, Color.teal.opacity(0.85), 2.2),
        (1.7, 0.72, Color.accentColor.opacity(0.75), 2.8),
        (3.1, 0.48, Color.indigo.opacity(0.8), 2.0),
        (4.4, 0.38, Color.cyan.opacity(0.55), 1.6),
    ]

    var body: some View {
        Group {
            if reduceMotion {
                reducedMotionBand
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isLive)) { timeline in
                    Canvas { context, size in
                        drawAurora(
                            context: context,
                            size: size,
                            time: timeline.date.timeIntervalSinceReferenceDate
                        )
                    }
                }
            }
        }
        .frame(height: Self.bandHeight)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .onChange(of: energy) { _, newValue in
            ingest(energy: CGFloat(newValue))
        }
        .onChange(of: isLive) { _, live in
            if !live { resetBand() }
        }
        .onAppear {
            ingest(energy: CGFloat(energy))
        }
    }

    private var accessibilityLabel: String {
        guard isLive else { return "Voice presence idle" }
        let level = Int((smoothedEnergy * 100).rounded())
        return isHearingSpeech
            ? "Listening, voice level \(level) percent"
            : "Listening, quiet"
    }

    private var reducedMotionBand: some View {
        LinearGradient(
            colors: [
                Color.accentColor.opacity(0.15 + smoothedEnergy * 0.35),
                Color.teal.opacity(0.12 + smoothedEnergy * 0.25),
                Color.indigo.opacity(0.18 + smoothedEnergy * 0.3),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .opacity(isLive ? 0.55 + smoothedEnergy * 0.45 : 0.25)
        .animation(.easeOut(duration: 0.2), value: smoothedEnergy)
    }

    private func resetBand() {
        samples = Array(repeating: Self.baseline, count: Self.sampleCount)
        smoothedEnergy = Self.baseline
    }

    private func ingest(energy raw: CGFloat) {
        let clamped = min(1, max(0, raw))
        // Slight attack/release so the band feels alive without jitter.
        let attack: CGFloat = clamped > smoothedEnergy ? 0.45 : 0.18
        smoothedEnergy += (clamped - smoothedEnergy) * attack
        let floor: CGFloat = isLive ? 0.06 : 0.04
        samples.append(max(floor, smoothedEnergy))
        if samples.count > Self.sampleCount {
            samples.removeFirst(samples.count - Self.sampleCount)
        }
    }

    private func drawAurora(context: GraphicsContext, size: CGSize, time: TimeInterval) {
        let w = size.width
        let h = size.height
        guard w > 1, h > 1 else { return }

        let energy = smoothedEnergy
        let live = isLive

        // Soft wash behind ribbons.
        var wash = context
        wash.opacity = live ? 0.22 + energy * 0.35 : 0.12
        wash.fill(
            Path(CGRect(origin: .zero, size: size)),
            with: .linearGradient(
                Gradient(colors: [
                    Color.teal.opacity(0.55),
                    Color.accentColor.opacity(0.4),
                    Color.indigo.opacity(0.55),
                ]),
                startPoint: CGPoint(x: 0, y: h * 0.5),
                endPoint: CGPoint(x: w, y: h * 0.5)
            )
        )

        for ribbon in Self.ribbons {
            let path = ribbonPath(width: w, height: h, time: time, ribbon: ribbon)
            var strokeContext = context
            strokeContext.opacity = live ? 0.55 + energy * 0.4 : 0.3
            strokeContext.stroke(
                path,
                with: .color(ribbon.color),
                style: StrokeStyle(lineWidth: ribbon.line, lineCap: .round, lineJoin: .round)
            )

            // Soft fill under ribbon for aurora body.
            var fillPath = path
            fillPath.addLine(to: CGPoint(x: w, y: h))
            fillPath.addLine(to: CGPoint(x: 0, y: h))
            fillPath.closeSubpath()
            var fillContext = context
            fillContext.opacity = live ? 0.08 + energy * 0.12 : 0.04
            fillContext.fill(fillPath, with: .color(ribbon.color))
        }
    }

    private func ribbonPath(
        width w: CGFloat,
        height h: CGFloat,
        time: TimeInterval,
        ribbon: (phase: Double, amp: CGFloat, color: Color, line: CGFloat)
    ) -> Path {
        var path = Path()
        let points = Self.ribbonPointCount
        let idle: CGFloat = isLive ? 0.12 : 0.06
        let lastSample = max(0, samples.count - 1)

        for i in 0...points {
            let t = CGFloat(i) / CGFloat(points)
            let x = t * w
            let sampleIndex = samples.isEmpty ? 0 : min(lastSample, Int(t * CGFloat(lastSample)))
            let localEnergy = samples.isEmpty ? smoothedEnergy : samples[sampleIndex]
            let amp = (idle + localEnergy * ribbon.amp) * h * 0.42
            let wave = sin(Double(t) * .pi * 2.4 + time * 1.6 + ribbon.phase)
                + 0.35 * sin(Double(t) * .pi * 5.1 - time * 1.1 + ribbon.phase * 0.7)
            let y = h * 0.55 + CGFloat(wave) * amp
            if i == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        return path
    }
}
