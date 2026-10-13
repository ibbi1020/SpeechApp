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

    private var chosen: PracticeFormat.Kind {
        model.chosenKind ?? .conversation
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

    private var motion: Animation {
        reduceMotion ? .easeOut(duration: 0.2) : SpeechMotion.swap
    }

    var body: some View {
        ZStack {
            CeremonyPalette.background
                .ignoresSafeArea()

            if model.ceremonyStep == .breathe {
                BreathCircle(fill: breathFill)
                    .ignoresSafeArea()
                    .transition(.opacity)
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
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 8)))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, SpeechSpacing.section)
                .padding(.bottom, SpeechSpacing.section)

                Button(action: commit) {
                    Text(control.title)
                        .contentTransition(.opacity)
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
            }
            if step != .hum { humPhase = .explain }
        }
    }

    @ViewBuilder
    private var step: some View {
        switch model.ceremonyStep {
        case .breathe:
            BreatheStep(fill: $breathFill) { done in
                breatheDone = done
            }
        case .exercise:
            ExerciseStep()
        case .hum:
            VocalStep(clip: clip, phase: humPhase) {
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
