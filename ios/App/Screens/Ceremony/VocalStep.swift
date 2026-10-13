import SpeechAppKit
import SwiftUI

/// Explain first, including the breath. The voice starts only after Ready, then runs
/// ten seconds, which is short enough to hold in one breath.
struct VocalStep: View {
    var clip: VocalClip
    var phase: HumPhase
    var onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: CGFloat = 0
    @State private var tone = HumTone()

    private var secondsLeft: Int {
        Int((VocalClip.seconds * Double(1 - progress)).rounded(.up))
    }

    var body: some View {
        Group {
            if phase == .explain {
                explain
            } else {
                playing
            }
        }
        .task(id: phase) {
            guard phase == .playing else { return }
            await run()
        }
        .onDisappear { tone.stop() }
    }

    private var explain: some View {
        VStack(alignment: .leading, spacing: SpeechSpacing.related) {
            Text(clip.explain)
                .ceremonyType(.display)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Text(CeremonyCopy.humBreath)
                .ceremonyType(.body)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }

    private var playing: some View {
        VStack(alignment: .leading, spacing: SpeechSpacing.section) {
            Text(clip.line)
                .ceremonyType(.display)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            TonePath(progress: reduceMotion ? 1 : progress)
                .frame(height: 16)
                .accessibilityLabel("Voice")
                .accessibilityValue(progress >= 1 ? "Finished" : "Playing")
            if progress < 1 {
                CeremonyMeasuredText(value: "\(max(secondsLeft, 1))", unit: "s")
                    .accessibilityLabel("\(max(secondsLeft, 1)) seconds")
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func run() async {
        progress = 0
        tone.play(clip)
        let clock = ContinuousClock()
        let start = clock.now
        let length = Duration.seconds(VocalClip.seconds)
        while Task.isCancelled == false {
            let fraction = min(1, start.duration(to: clock.now) / length)
            progress = CGFloat(fraction)
            if fraction >= 1 {
                progress = 1
                onFinished()
                return
            }
            try? await Task.sleep(for: .milliseconds(16))
        }
    }
}

/// White line that draws left to right, with a dot at the leading end.
private struct TonePath: View {
    var progress: CGFloat

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let drawn = max(0, min(1, progress)) * width
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.18))
                    .frame(height: 2)
                Capsule()
                    .fill(Color.white)
                    .frame(width: drawn, height: 2)
                Circle()
                    .fill(Color.white)
                    .frame(width: 8, height: 8)
                    .offset(x: min(max(0, drawn - 4), max(0, width - 8)))
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
    }
}
