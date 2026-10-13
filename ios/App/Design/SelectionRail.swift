import SwiftUI

/// A row of options you pick between. Every option is visible at once and the row
/// never scrolls, so nothing can sit half off the screen edge.
///
/// Selection reads as fill, not scale: the chosen card is solid and its content
/// inverts, matching the primary button. The rest are a faint wash. Scaling cards in
/// a tight row only makes the gaps look broken.
struct SelectionRail<ID: Hashable, Card: View>: View {
    let ids: [ID]
    @Binding var selection: ID
    var card: (ID, Bool) -> Card

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let spacing: CGFloat = 10
    private let radius: CGFloat = 18

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(ids, id: \.self) { id in
                let selected = id == selection
                Button {
                    withAnimation(motion) { selection = id }
                } label: {
                    card(id, selected)
                        .padding(.horizontal, SpeechSpacing.cluster)
                        .frame(maxWidth: .infinity)
                        .frame(height: 68)
                        .background(fill(selected), in: shape)
                        .overlay {
                            shape.strokeBorder(
                                selected ? .clear : .white.opacity(0.14),
                                lineWidth: 1
                            )
                        }
                        .foregroundStyle(selected ? Color.black : Color.white.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
        .accessibilityElement(children: .contain)
        .accessibilityAdjustableAction { adjustment in
            guard let index = ids.firstIndex(of: selection) else { return }
            switch adjustment {
            case .increment:
                select(index: index + 1)
            case .decrement:
                select(index: index - 1)
            @unknown default:
                break
            }
        }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
    }

    private func fill(_ selected: Bool) -> Color {
        selected ? .white : .white.opacity(0.07)
    }

    private var motion: Animation {
        reduceMotion ? .easeOut(duration: 0.2) : SpeechMotion.press
    }

    private func select(index: Int) {
        guard ids.indices.contains(index) else { return }
        selection = ids[index]
    }
}
