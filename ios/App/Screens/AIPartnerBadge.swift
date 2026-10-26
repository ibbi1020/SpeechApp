import SwiftUI

/// Persistent SB 243 notice. Same plate as the voice and background circles.
/// Collapsed it is that circle, labeled “AI”. A tap grows the notice from that edge.
struct AIPartnerBadge: View {
    /// A place picture is behind the column. The plate turns solid.
    var overPicture: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @State private var expanded = false

    /// Counsel has not written a longer line. Do not invent one.
    static let notice = "This partner is AI, not a person."

    /// Matches the voice and background circles so the column shares one trailing edge.
    private static let column: CGFloat = SpeechIconCircleStyle.standard

    private var usesSolid: Bool {
        ConversationSurface.usesSolid(
            overPicture: overPicture,
            reduceTransparency: reduceTransparency
        )
    }

    var body: some View {
        Button {
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : SpeechMotion.settle) {
                expanded.toggle()
            }
        } label: {
            Text(expanded ? Self.notice : "AI")
                .font(expanded ? .caption.weight(.semibold) : .body.weight(.semibold))
                .tracking(expanded ? 0 : 0.4)
                .foregroundStyle(usesSolid ? Color.black : Color.white)
                .multilineTextAlignment(expanded ? .leading : .center)
                .lineLimit(expanded ? 3 : 1)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, expanded ? 14 : 0)
                .padding(.vertical, expanded ? 10 : 0)
                .frame(
                    width: expanded ? 196 : Self.column,
                    height: expanded ? nil : Self.column,
                    alignment: expanded ? .leading : .center
                )
                .frame(minHeight: expanded ? Self.column : nil)
                .modifier(ConversationSurfacePlate(overPicture: overPicture, kind: .capsule))
                .contentTransition(.opacity)
        }
        .buttonStyle(AIPartnerBadgePressStyle())
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
