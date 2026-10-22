import SwiftUI
import SpeechAppKit

/// SwiftUI stand-in for the conversation orb. The live orb is a WebView, which a widget cannot host.
struct IslandOrb: View {
    var look: ConversationActivityOrb
    var size: CGFloat

    var body: some View {
        Circle()
            .fill(gradient)
            .overlay {
                Circle()
                    .strokeBorder(.white.opacity(look == .paused ? 0.15 : 0.35), lineWidth: 0.5)
            }
            .frame(width: size, height: size)
            .opacity(look == .paused ? 0.45 : 1)
            .accessibilityLabel(label)
    }

    private var gradient: LinearGradient {
        LinearGradient(
            colors: [Self.highlight, Self.upper, Self.deep],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var label: String {
        switch look {
        case .listening: "Listening"
        case .speaking: "Speaking"
        case .paused: "Paused"
        }
    }

    /// Cloud-orb periwinkle, flattened for a 24pt chip.
    private static let deep = Color(red: 0.36, green: 0.39, blue: 0.985)
    private static let upper = Color(red: 0.48, green: 0.56, blue: 0.985)
    private static let highlight = Color(red: 0.89, green: 0.92, blue: 0.995)
}
