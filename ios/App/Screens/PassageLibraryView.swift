import SwiftUI
import SpeechAppKit

/// The passage list. Titles scroll under a soft blur at the top and the bottom,
/// the same edge treatment the system uses when content meets a bar.
struct PassageLibraryView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Passages")
                    .speechType(.h1)
                    .foregroundStyle(.primary)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, SpeechSpacing.related)

                Text("Pick one to read aloud.")
                    .ceremonyType(.body)
                    .foregroundStyle(.secondary)
                    .padding(.top, SpeechSpacing.related)

                if model.catalog.pickerPassages.isEmpty {
                    Text("Passages didn’t load. Go back and try again.")
                        .ceremonyType(.body)
                        .foregroundStyle(.secondary)
                        .padding(.top, SpeechSpacing.section)
                } else {
                    LazyVStack(spacing: 4) {
                        ForEach(model.catalog.pickerPassages) { passage in
                            PassageLibraryRow(title: passage.title) {
                                model.selectPassage(passage)
                            }
                        }
                    }
                    .padding(.top, SpeechSpacing.section)
                }
            }
            .padding(.horizontal, SpeechSpacing.page)
            .padding(.bottom, SpeechSpacing.page)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .scrollEdgeEffectStyle(.soft, for: .bottom)
        .safeAreaBar(edge: .top, spacing: 0) {
            GlassCircleButton(systemName: "chevron.left", label: "Back") {
                dismiss()
            }
            .padding(.horizontal, SpeechSpacing.page)
            .padding(.vertical, SpeechSpacing.cluster)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .safeAreaBar(edge: .bottom, spacing: 0) {
            Color.clear
                .frame(height: 28)
                .accessibilityHidden(true)
        }
        .background {
            CeremonyPalette.background
                .ignoresSafeArea()
        }
        .navigationTitle("Passages")
        .toolbar(.hidden, for: .navigationBar)
        .background(SpeechEdgeSwipe())
    }
}

/// A passage title. Opacity tracks the scroll: the row is solid once about
/// 70% of it is on screen, and it fades as it leaves either edge.
private struct PassageLibraryRow: View {
    let title: String
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 17pt was the body size. A main list row wants about 60% more presence.
    @ScaledMetric(relativeTo: .title) private var titleSize: CGFloat = 27

    var body: some View {
        let row = Button(action: action) {
            Text(title)
                .font(.system(size: titleSize, weight: .semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(PassageRowButtonStyle())
        .accessibilityLabel(title)

        if reduceMotion {
            row
        } else {
            row.scrollTransition(.interactive.threshold(.visible(0.7)), axis: .vertical) { content, phase in
                content.opacity(phase.isIdentity ? 1 : 0)
            }
        }
    }
}

private struct PassageRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(SpeechMotion.press, value: configuration.isPressed)
    }
}
