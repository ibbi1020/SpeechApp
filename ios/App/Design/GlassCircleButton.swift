import SwiftUI

/// Solid circle control. White glyph on a 12% white disc.
struct GlassCircleButton: View {
    let systemName: String
    let label: String
    let diameter: CGFloat = SpeechIconCircleStyle.standard
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
        }
        .buttonStyle(SpeechIconCircleStyle(diameter: diameter))
        .accessibilityLabel(label)
    }
}
