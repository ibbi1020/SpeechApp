import SwiftUI

/// Persistent SB 243 notice. A glass capsule in the same column as the session
/// buttons. Collapsed to “AI”; a tap grows it from that edge.
struct AIPartnerBadge: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @State private var expanded = false

    /// Counsel has not written a longer line. Do not invent one.
    static let notice = "This partner is AI, not a person."

    /// Matches the session glass buttons so the column shares one trailing edge.
    private static let column: CGFloat = 48

    var body: some View {
        Button {
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : SpeechMotion.settle) {
                expanded.toggle()
            }
        } label: {
            Text(expanded ? Self.notice : "AI")
                .font(.caption.weight(.semibold))
                .tracking(expanded ? 0 : 0.4)
                .foregroundStyle(.primary)
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
                .background {
                    if reduceTransparency {
                        Capsule().fill(Color.primary.opacity(0.12))
                    }
                }
                .glassEffect(
                    reduceTransparency ? .identity : .regular.interactive(),
                    in: .capsule
                )
                .contentTransition(.opacity)
        }
        .buttonStyle(AIPartnerBadgePressStyle())
        .frame(minHeight: 44)
        .accessibilityLabel("AI partner. \(Self.notice)")
        .accessibilityHint(expanded ? "Hides the full notice." : "Shows the full notice.")
        .accessibilityInputLabels(["AI", "AI partner"])
    }
}

/// Press scales from the current size. The glass highlight is the material's own.
private struct AIPartnerBadgePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(SpeechMotion.press, value: configuration.isPressed)
    }
}
