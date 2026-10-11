import SwiftUI

/// A full-bleed dithered plate. Draft 1 ships these as bundled images; nearest-neighbour
/// sampling is deliberate so the dots stay hard-edged when the plate is scaled up.
///
/// `resolve` cross-fades a coarse plate into the fine one: 0 is coarse, 1 is fine.
/// Both plates are opaque, so the coarse one occludes rather than washing out the fine one.
struct DitherPlate: View {
    let name: String
    var coarseName: String?
    var resolve: Double = 1

    var body: some View {
        ZStack {
            Color.black
            plate(name)
            if let coarseName, resolve < 1 {
                plate(coarseName).opacity(1 - resolve)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private func plate(_ name: String) -> some View {
        Image(name)
            .resizable()
            .interpolation(.none)
            .scaledToFill()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
    }
}

/// Keeps text legible where it sits over the plate. Scrims only the two edges the
/// copy occupies, so the figure in the middle band stays untouched.
struct DitherPlateScrim: View {
    var body: some View {
        LinearGradient(
            stops: [
                .init(color: .black.opacity(0.9), location: 0),
                .init(color: .black.opacity(0.78), location: 0.16),
                .init(color: .black.opacity(0.3), location: 0.33),
                .init(color: .clear, location: 0.46),
                .init(color: .clear, location: 0.6),
                .init(color: .black.opacity(0.4), location: 0.82),
                .init(color: .black.opacity(0.92), location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
