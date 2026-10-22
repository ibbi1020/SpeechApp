import SpeechAppKit
import SwiftUI

/// Pick the exercise. The name and the line sit up top. Three discs sit above
/// the button. Each one is swirling gas in that exercise's colour, so it reads
/// as a control. The chosen gas churns. The other two slow down, fade to gray,
/// and are pushed off it.
///
/// The discs do not carry words. The name is the kicker, because a blank disc
/// cannot say "Reading" and the heading should not have to.
struct ExerciseStep: View {
    /// Shown when the microphone cannot be used to check the room.
    var blocked: String?

    @Environment(AppModel.self) private var model

    private var counts: WeeklyPracticeCounts { model.weeklyCounts }

    private var offer: ExerciseOffer {
        ExerciseOfferMaker.offer(counts: counts, conversationAvailable: model.budget.startEnabled)
    }

    private var selected: PracticeFormat.Kind { model.chosenKind ?? offer.proposed }

    private var selection: Binding<PracticeFormat.Kind> {
        Binding(get: { selected }, set: { model.chosenKind = $0 })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            heading
            Spacer(minLength: 0)
            MagneticSelect(selection: selection)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { if model.chosenKind == nil { model.chosenKind = offer.proposed } }
    }

    private var heading: some View {
        let format = PracticeFormat.all.first { $0.kind == selected }
        let history = ExerciseOfferMaker.history(
            for: selected, counts: counts, proposed: offer.proposed
        )
        let note = PracticeFormat.startControl(for: selected, budget: model.budget).note
        // Picking a different exercise rewrites the name, the line, and whatever
        // history is showing. They dissolve through blur rather than cross-fading,
        // so the heading never reads as two overlaid sentences mid-swap. Each line
        // blurs at its own type size.
        return VStack(alignment: .leading, spacing: SpeechSpacing.cluster) {
            BlurDissolve(format?.title ?? "", size: CeremonyType.metrics(.label).size) { name in
                Text(name)
                    .ceremonyType(.label)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: SpeechSpacing.related) {
                BlurDissolve(format?.line ?? "", size: CeremonyType.metrics(.display).size) { line in
                    Text(line)
                        .ceremonyType(.display)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let history {
                    BlurDissolve(history, size: CeremonyType.metrics(.body).size) { line in
                        Text(line)
                            .ceremonyType(.body)
                            .foregroundStyle(.secondary)
                    }
                }
                if let note {
                    BlurDissolve(note, size: CeremonyType.metrics(.body).size) { line in
                        Text(line)
                            .ceremonyType(.body)
                            .foregroundStyle(.tertiary)
                    }
                }
                if let blocked {
                    BlurDissolve(blocked, size: CeremonyType.metrics(.body).size) { line in
                        Text(line)
                            .ceremonyType(.body)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .animation(SpeechMotion.swap, value: selected)
        .accessibilityElement(children: .combine)
    }
}
