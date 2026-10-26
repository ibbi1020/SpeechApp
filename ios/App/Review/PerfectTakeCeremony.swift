import Lottie
import SwiftUI
import SpeechAppKit

/// A take with nothing left to mark. Too short to score does not count:
/// `maxMarkers` is 0 under about 1.5 seconds, and an empty list there can mean
/// the cap threw the moments away.
enum PerfectTake {
    static let green = Color(red: 48.0 / 255, green: 209.0 / 255, blue: 88.0 / 255).opacity(0.62)
    static let line = "That was perfect. \u{1F44F}"
    static let lineLabel = "That was perfect."

    static func isClean(_ take: RecordingManifest.Take) -> Bool {
        take.markers.isEmpty && ReviewMarkers.maxMarkers(durationSeconds: take.durationSeconds) > 0
    }

    static func recordingIsClean(_ manifest: RecordingManifest) -> Bool {
        manifest.saveError == nil
            && !manifest.takes.isEmpty
            && manifest.takes.allSatisfy(isClean)
    }
}

/// Pause wash, falling confetti, and the two lines, once, when a whole recording
/// has nothing to mark. The report underneath stays put. This view only covers it.
struct PerfectTakeCeremony: View {
    @Binding var contentBlur: CGFloat
    var onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ScaledMetric private var headlineSize: CGFloat
    @State private var veil: CGFloat
    @State private var words: CGFloat
    @State private var confetti: CGFloat
    @State private var generation: Int
    @State private var started: Bool
    @State private var hold: Task<Void, Never>?

    init(contentBlur: Binding<CGFloat>, onFinished: @escaping () -> Void) {
        _contentBlur = contentBlur
        self.onFinished = onFinished
        let metrics = SpeechType.metrics(.h2)
        _headlineSize = ScaledMetric(wrappedValue: metrics.size, relativeTo: metrics.relativeTo)
        _veil = State(initialValue: 0)
        _words = State(initialValue: 0)
        _confetti = State(initialValue: 0)
        _generation = State(initialValue: 0)
        _started = State(initialValue: false)
        _hold = State(initialValue: nil)
    }

    var body: some View {
        ZStack {
            PauseWash(
                progress: veil,
                reduceMotion: reduceMotion,
                bottomOpacity: reduceTransparency
                    ? PauseVeilMotion.opaqueWashOpacity
                    : PauseVeilMotion.washOpacity
            )
            if !reduceMotion {
                LottieView {
                    try await DotLottieFile.named("ConfettiFalling")
                }
                .playing()
                .resizable()
                .configure { view in
                    view.contentMode = .scaleAspectFill
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .ignoresSafeArea()
                .opacity(confetti)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            VStack(spacing: 16) {
                Text("That was perfect.")
                    .speechType(.h2)
                    .foregroundStyle(.white)
                Text("No feedback. Good job.")
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color(white: PauseVeilMotion.labelWhite))
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, SpeechSpacing.page)
            .opacity(words)
            .blur(radius: wordBlur)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("That was perfect. No feedback. Good job.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onAppear {
            guard !started else { return }
            started = true
            play()
        }
        .onDisappear {
            generation += 1
            hold?.cancel()
            contentBlur = 0
        }
    }

    private var wordBlur: CGFloat {
        guard !reduceMotion, !reduceTransparency else { return 0 }
        return (1 - words) * BlurMotion.textRadius(forSize: headlineSize)
    }

    private var veilAnimation: Animation {
        .easeOut(duration: reduceMotion ? BlurMotion.reducedFade : PauseVeilMotion.veil)
    }

    private var wordAnimation: Animation {
        .easeInOut(duration: reduceMotion ? BlurMotion.reducedFade : BlurMotion.dissolve)
    }

    private var holdSeconds: TimeInterval {
        reduceMotion ? 0.7 : 2.2
    }

    private func shownBlur(for veil: CGFloat) -> CGFloat {
        guard !reduceMotion, !reduceTransparency else { return 0 }
        return veil * PauseVeilMotion.blurRadius
    }

    /// Veil climbs, then the words resolve, hold, words leave, veil drops.
    /// A newer `generation` means the screen went away. That pass stops.
    private func play() {
        generation += 1
        let gate = generation
        withAnimation(veilAnimation) {
            veil = 1
            if !reduceMotion {
                confetti = 1
            }
            contentBlur = shownBlur(for: 1)
        } completion: {
            guard gate == generation else { return }
            withAnimation(wordAnimation) {
                words = 1
            } completion: {
                guard gate == generation else { return }
                hold = Task { @MainActor in
                    try? await Task.sleep(for: .seconds(holdSeconds))
                    guard !Task.isCancelled, gate == generation else { return }
                    leave(gate: gate)
                }
            }
        }
    }

    private func leave(gate: Int) {
        withAnimation(wordAnimation) {
            words = 0
            confetti = 0
        } completion: {
            guard gate == generation else { return }
            withAnimation(veilAnimation) {
                veil = 0
                contentBlur = shownBlur(for: 0)
            } completion: {
                guard gate == generation else { return }
                onFinished()
            }
        }
    }
}
