import SwiftUI

/// 48pt circular control. Glass when transparency is allowed, a solid disc when it is not.
struct GlassCircleButton: View {
    let systemName: String
    let label: String
    let action: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 48, height: 48)
                .background {
                    if reduceTransparency {
                        Circle().fill(Color(.secondarySystemBackground))
                        Circle().strokeBorder(Color.primary.opacity(0.35), lineWidth: 1)
                    }
                }
                .modifier(GlassCircleChrome(allowsGlass: reduceTransparency == false))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

private struct GlassCircleChrome: ViewModifier {
    var allowsGlass: Bool

    func body(content: Content) -> some View {
        if allowsGlass {
            content.glassEffect(.regular.interactive(), in: .circle)
        } else {
            content
        }
    }
}
