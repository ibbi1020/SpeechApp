import SpeechAppKit
import SwiftUI

/// Pick the exercise. What it is, stated once, over three names.
///
/// Earlier versions stacked an icon, a name and a count inside each card while the
/// heading repeated the same name above them. Three ways of saying "Reading" on one
/// screen. The card carries the name and nothing else; the heading describes it.
struct ExerciseStep: View {
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
            Spacer(minLength: SpeechSpacing.section)
            heading
                .padding(.bottom, SpeechSpacing.section)
            SelectionRail(ids: PracticeFormat.all.map(\.kind), selection: selection) { kind, _ in
                Text(PracticeFormat.all.first { $0.kind == kind }?.title ?? "")
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
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
        // Picking a different exercise rewrites all three lines. They dissolve through
        // blur rather than cross-fading, so the heading never reads as two overlaid
        // sentences mid-swap. Each line blurs at its own type size.
        return VStack(alignment: .leading, spacing: SpeechSpacing.cluster) {
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
                .padding(.top, SpeechSpacing.cluster)
            }
            if let note {
                BlurDissolve(note, size: CeremonyType.metrics(.body).size) { line in
                    Text(line)
                        .ceremonyType(.body)
                        .foregroundStyle(.tertiary)
                }
                .padding(.top, SpeechSpacing.cluster)
            }
        }
        .animation(SpeechMotion.swap, value: selected)
        .accessibilityElement(children: .combine)
    }
}
