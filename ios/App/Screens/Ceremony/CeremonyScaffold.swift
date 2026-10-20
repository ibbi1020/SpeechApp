import SwiftUI
import SpeechAppKit

/// One surface for the whole ceremony. The background and the white button never
/// unmount. Only the middle, and the button's label, change. That is how FocusFlight
/// keeps five screens feeling like one journey.
struct CeremonyScaffold: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breatheDone = false
    @State private var humPhase: HumPhase = .explain
    @State private var clip = HumTone.rotate()
    @State private var breathFill: CGFloat = 0
    @State private var showCircle = false
    @State private var humProgress: CGFloat = 0
    @State private var humVoice: Double = 0

    private var chosen: PracticeFormat.Kind {
        model.chosenKind ?? .conversation
    }

    /// The plate has to match the step on the first frame. `chosenKind` is still
    /// nil until the step proposes one, and falling back to conversation would
    /// dissolve the wrong field in.
    private var exerciseKind: PracticeFormat.Kind {
        if let kind = model.chosenKind { return kind }
        return ExerciseOfferMaker.offer(
            counts: model.weeklyCounts,
            conversationAvailable: model.budget.startEnabled
        ).proposed
    }

    private var control: CeremonyControl {
        CeremonyControls.control(
            step: model.ceremonyStep,
            chosen: chosen,
            budget: model.budget,
            breatheDone: breatheDone,
            humPhase: humPhase
        )
    }

    /// Blur curve, not the spring: every change on this surface is now a dissolve,
    /// and a spring on a blur radius reads as the lens hunting for focus.
    private var motion: Animation {
        SpeechBlur.motion(reduceMotion: reduceMotion)
    }

    var body: some View {
        ZStack {
            CeremonyPalette.background
                .ignoresSafeArea()

            if model.ceremonyStep == .breathe, showCircle {
                BreathCircle(fill: breathFill)
                    .ignoresSafeArea()
                    .transition(SpeechBlur.dissolve)
            }

            if model.ceremonyStep == .hum {
                HumField(voice: humVoice)
                    .ignoresSafeArea()
                    .transition(SpeechBlur.dissolve)
            }

            if model.ceremonyStep == .exercise {
                ExerciseField(kind: exerciseKind)
                    .ignoresSafeArea()
                    .transition(SpeechBlur.dissolve)
                ExerciseScrim()
                    .ignoresSafeArea()
            }

            VStack(alignment: .leading, spacing: 0) {
                GlassCircleButton(systemName: "chevron.left", label: "Back") {
                    breatheDone = false
                    humPhase = .explain
                    model.retreatCeremony()
                }

                ZStack {
                    step
                        .id(model.ceremonyStep)
                        .transition(SpeechBlur.dissolve)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, SpeechSpacing.section)
                .padding(.bottom, SpeechSpacing.section)

                // The button is the one thing that never unmounts, so its label has to
                // carry the step change on its own. Blur does that without the capsule
                // resizing mid-word, which is what a width-animating swap would do.
                Button(action: commit) {
                    BlurDissolve(control.title, size: SpeechStartMetrics.labelSize) { title in
                        Text(title)
                    }
                }
                .buttonStyle(SpeechStartButtonStyle())
                .disabled(control.isEnabled == false)
            }
            .padding(.horizontal, SpeechSpacing.page)
            .padding(.top, SpeechSpacing.related)
            .padding(.bottom, SpeechSpacing.page)
        }
        .animation(motion, value: model.ceremonyStep)
        .sensoryFeedback(.impact(weight: .medium, intensity: 0.7), trigger: model.ceremonyStep)
        .onChange(of: model.ceremonyStep) { _, step in
            if step != .breathe {
                breatheDone = false
                breathFill = 0
                showCircle = false
            }
            if step != .hum {
                humPhase = .explain
                humProgress = 0
                humVoice = 0
            }
        }
    }

    @ViewBuilder
    private var step: some View {
        switch model.ceremonyStep {
        case .breathe:
            BreatheStep(fill: $breathFill, showCircle: $showCircle) { done in
                breatheDone = done
            }
        case .exercise:
            ExerciseStep()
        case .hum:
            VocalStep(clip: clip, phase: humPhase, progress: $humProgress, voice: $humVoice) {
                humPhase = .finished
            }
        case .note, .purpose, .speak:
            EmptyView()
        }
    }

    private func commit() {
        switch control.advance {
        case .step:
            model.advanceCeremony()
        case .armHum:
            humPhase = .playing
        case .start:
            model.finishCeremony()
        }
    }
}
