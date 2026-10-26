import SpeechAppKit
import SwiftUI

/// Explain first, including the breath. The sound starts only after they tap,
/// then runs ten seconds, which is short enough to hold in one breath.
struct VocalStep: View {
    var clip: VocalClip
    var phase: HumPhase
    @Binding var progress: CGFloat
    @Binding var voice: Double
    var onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tone = HumTone()

    private var secondsLeft: Int {
        Int((VocalClip.seconds * Double(1 - progress)).rounded(.up))
    }

    var body: some View {
        Group {
            if phase == .explain {
                explain
                    .transition(SpeechBlur.dissolve)
            } else {
                playing
                    .transition(SpeechBlur.dissolve)
            }
        }
        .animation(SpeechBlur.motion(reduceMotion: reduceMotion), value: phase)
        .task(id: phase) {
            guard phase == .playing else { return }
            await run()
        }
        .task {
            await tone.listen()
            while Task.isCancelled == false {
                voice = tone.voice
                try? await Task.sleep(for: .milliseconds(32))
            }
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
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }

    private var playing: some View {
        VStack(alignment: .leading, spacing: SpeechSpacing.related) {
            Text(clip.line)
                .ceremonyType(.display)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            TonePath(progress: reduceMotion ? 1 : progress)
                .frame(height: 16)
                .accessibilityLabel("Voice")
                .accessibilityValue(progress >= 1 ? "Finished" : "Playing")
            if progress < 1 {
                // The line and the mic redraw many times a second. The seconds
                // have to sit in their own view or those redraws cancel the roll.
                HumCountdown(seconds: max(secondsLeft, 1), reduceMotion: reduceMotion)
                    .equatable()
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func run() async {
        progress = 0
        // play() waits until the tone finishes. The line has to move while that happens.
        async let playback: Void = tone.play(clip)
        let clock = ContinuousClock()
        let start = clock.now
        let length = Duration.seconds(VocalClip.seconds)
        while Task.isCancelled == false {
            let fraction = min(1, start.duration(to: clock.now) / length)
            progress = CGFloat(fraction)
            if fraction >= 1 {
                progress = 1
                onFinished()
                break
            }
            try? await Task.sleep(for: .milliseconds(16))
        }
        await playback
    }
}

/// Whole seconds of the hum. Equatable so a tone redraw does not rebuild the
/// digits while they are still rolling.
private struct HumCountdown: View, Equatable {
    var seconds: Int
    var reduceMotion: Bool

    var body: some View {
        CeremonyMeasuredText(
            value: "\(seconds)",
            unit: "s",
            countsDown: true,
            reduceMotion: reduceMotion
        )
        .accessibilityLabel("\(seconds) seconds")
        .accessibilityAddTraits(.updatesFrequently)
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
