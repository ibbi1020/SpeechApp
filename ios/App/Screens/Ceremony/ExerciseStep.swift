import SpeechAppKit
import SwiftUI

/// Pick the exercise. The name and the line sit up top. Three cards sit above
/// the button, in the button's column. The chosen card is white with a black
/// icon. The other two are a hairline and a white icon.
///
/// The cards do not carry words. The name is the kicker, because an icon
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
            ExerciseCards(selection: selection)
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

/// Three cards, exactly as wide as the start button. Flight-card proportion,
/// icon only. The gas discs in `MagneticSelect` are unplugged, not removed.
struct ExerciseCards: View {
    @Binding var selection: PracticeFormat.Kind

    var body: some View {
        HStack(spacing: SpeechSpacing.tight) {
            ForEach(PracticeFormat.all) { format in
                card(format)
            }
        }
        .padding(.horizontal, SpeechStartMetrics.extraInset)
        .animation(SpeechMotion.swap, value: selection)
        .sensoryFeedback(.selection, trigger: selection)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Exercise")
        .accessibilityAdjustableAction { adjustment in
            guard let index = PracticeFormat.all.firstIndex(where: { $0.kind == selection }) else { return }
            let next: Int
            switch adjustment {
            case .increment: next = index + 1
            case .decrement: next = index - 1
            @unknown default: return
            }
            let kinds = PracticeFormat.all.map(\.kind)
            guard kinds.indices.contains(next) else { return }
            selection = kinds[next]
        }
    }

    private func card(_ format: PracticeFormat) -> some View {
        let chosen = format.kind == selection
        return Button(format.title, systemImage: Self.symbol(for: format.kind)) {
            selection = format.kind
        }
        .labelStyle(.iconOnly)
        .buttonStyle(ExerciseCardButtonStyle(chosen: chosen))
        .frame(maxWidth: .infinity)
        .accessibilityAddTraits(chosen ? .isSelected : [])
        .accessibilityRemoveTraits(chosen ? [] : .isSelected)
    }

    /// Filled, so the card reads at a glance. Open book, mic, person speaking.
    private static func symbol(for kind: PracticeFormat.Kind) -> String {
        switch kind {
        case .reading: "book.fill"
        case .monologue: "mic.fill"
        case .conversation: "person.wave.2.fill"
        }
    }
}

/// White when chosen, a gray-white hairline when not. The border stays in
/// both states so the card does not change size as the fill appears.
private struct ExerciseCardButtonStyle: ButtonStyle {
    var chosen: Bool

    private static let proportion: CGFloat = 3.0 / 3.7
    /// Continuous curvature (`RoundedCornerStyle.continuous`) on the 4pt scale.
    private static let radius: CGFloat = 20
    private static let hairline = Color(red: 228.0 / 255, green: 228.0 / 255, blue: 232.0 / 255).opacity(0.55)

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
        Color.clear
            .aspectRatio(Self.proportion, contentMode: .fit)
            .overlay {
                configuration.label
                    .font(.system(size: 28, weight: .medium))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(chosen ? Color.black : Color.white)
            }
            .background(chosen ? Color.white : Color.clear, in: shape)
            .overlay {
                shape.strokeBorder(chosen ? Color.white : Self.hairline, lineWidth: 1)
            }
            .contentShape(shape)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(SpeechMotion.press, value: configuration.isPressed)
    }
}
