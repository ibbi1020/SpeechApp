import SwiftUI

/// A full-bleed dithered plate. Draft 1 ships these as bundled images; nearest-neighbour
/// sampling is deliberate so the dots stay hard-edged when the plate is scaled up.
struct DitherPlate: View {
    let name: String
    /// Lowers the image by this fraction of the screen height, for plates whose figure
    /// sits high enough to run into the copy. The gap it opens at the top is black.
    var drop: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            Image(name)
                .resizable()
                .interpolation(.none)
                .scaledToFill()
                .frame(width: proxy.size.width, height: proxy.size.height)
                .offset(y: proxy.size.height * drop)
                .clipped()
        }
        .background(Color.black)
        .ignoresSafeArea()
        .accessibilityHidden(true)
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
