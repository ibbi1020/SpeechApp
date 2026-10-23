import SwiftUI

/// Persistent SB 243 notice. A solid white capsule in the same column as the
/// session circles. Collapsed to “AI”; a tap grows it from that edge.
struct AIPartnerBadge: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var expanded = false

    /// Counsel has not written a longer line. Do not invent one.
    static let notice = "This partner is AI, not a person."

    /// Matches the voice and background circles so the column shares one trailing edge.
    private static let column: CGFloat = SpeechIconCircleStyle.standard

    var body: some View {
        Button {
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : SpeechMotion.settle) {
                expanded.toggle()
            }
        } label: {
            Text(expanded ? Self.notice : "AI")
                .font(.caption.weight(.semibold))
                .tracking(expanded ? 0 : 0.4)
                .foregroundStyle(Color.black)
                .multilineTextAlignment(.leading)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, expanded ? 12 : 0)
                .padding(.vertical, expanded ? 8 : 0)
                .frame(
                    width: expanded ? 196 : Self.column,
                    height: expanded ? nil : 36,
                    alignment: expanded ? .leading : .center
                )
                .background(Color.white, in: Capsule())
                .contentTransition(.opacity)
        }
        .buttonStyle(AIPartnerBadgePressStyle())
        .frame(minHeight: 44)
        .accessibilityLabel("AI partner. \(Self.notice)")
        .accessibilityHint(expanded ? "Hides the full notice." : "Shows the full notice.")
        .accessibilityInputLabels(["AI", "AI partner"])
    }
}

/// Same press as the wide capsule. The badge keeps its own size as it expands.
private struct AIPartnerBadgePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(SpeechMotion.press, value: configuration.isPressed)
    }
}
