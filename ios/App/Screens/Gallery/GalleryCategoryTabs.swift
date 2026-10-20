import SpeechAppKit
import SwiftUI
import UIKit

/// Mail-style category selector. Idle tabs are icon capsules. The selected
/// one grows from that capsule and shows its name.
/// Proportions follow the skecher Apple Mail tabs, sized to sit under the gallery title.
struct GalleryCategoryTabs: View {
    var filters: [GalleryFilter]
    @Binding var selection: RecordingManifest.Format?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let pill = Animation.interpolatingSpring(mass: 0.8, stiffness: 420, damping: 36)

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(filters) { filter in
                        GalleryCategoryTab(
                            filter: filter,
                            isSelected: selection == filter.format,
                            reduceMotion: reduceMotion
                        ) {
                            selection = filter.format
                        }
                        .id(filter.id)
                    }
                }
                .padding(.horizontal, 16)
            }
            .scrollClipDisabled()
            .onChange(of: selection) { _, _ in
                guard let selected = filters.first(where: { $0.format == selection }) else { return }
                withAnimation(reduceMotion ? nil : Self.pill) {
                    proxy.scrollTo(selected.id, anchor: .center)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Categories")
        .sensoryFeedback(.selection, trigger: selection)
    }
}

private struct GalleryCategoryTab: View {
    var filter: GalleryFilter
    var isSelected: Bool
    var reduceMotion: Bool
    var action: () -> Void

    /// Visual size matches a subheadline chip. The button around it stays a 44pt target.
    private static let height: CGFloat = 32
    private static let closedWidth: CGFloat = 44
    private static let iconBox: CGFloat = 18
    private static let iconSize: CGFloat = 15
    private static let labelSize: CGFloat = 15
    private static let sidePad: CGFloat = 12
    private static let gap: CGFloat = 6

    private static let pill = Animation.interpolatingSpring(mass: 0.8, stiffness: 420, damping: 36)

    private var labelWidth: CGFloat {
        let font = UIFont.systemFont(ofSize: Self.labelSize, weight: .semibold)
        return ceil((filter.title as NSString).size(withAttributes: [.font: font]).width)
    }

    /// Side padding, the icon box, the gap, then the name. Matches the HStack exactly.
    private var openWidth: CGFloat {
        Self.sidePad * 2 + Self.iconBox + Self.gap + labelWidth
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Self.gap) {
                Image(systemName: filter.symbol)
                    .font(.system(size: Self.iconSize, weight: .semibold))
                    .symbolRenderingMode(.monochrome)
                    .frame(width: Self.iconBox, height: Self.iconBox)
                if isSelected {
                    Text(filter.title)
                        .font(.system(size: Self.labelSize, weight: .semibold))
                        .lineLimit(1)
                        .fixedSize()
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, isSelected ? Self.sidePad : 0)
            .frame(width: isSelected ? openWidth : Self.closedWidth, height: Self.height)
            .animation(reduceMotion ? .easeOut(duration: 0.2) : Self.pill, value: isSelected)
        }
        .buttonStyle(GalleryCategoryTabStyle(isSelected: isSelected))
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityLabel(filter.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct GalleryCategoryTabStyle: ButtonStyle {
    var isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        let fill: Color = if isSelected {
            configuration.isPressed ? Color(white: 0.86) : .white
        } else if configuration.isPressed {
            Color(white: 0.34)
        } else {
            Color(white: 0.24)
        }
        let foreground: Color = isSelected ? .black : .white
        configuration.label
            .foregroundStyle(foreground)
            .background(fill, in: Capsule())
            .clipShape(Capsule())
            .animation(.easeOut(duration: 0.2), value: isSelected)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
