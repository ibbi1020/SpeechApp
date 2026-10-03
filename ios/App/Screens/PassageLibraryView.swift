import SwiftUI
import SpeechAppKit

struct PassageLibraryView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            ForEach(model.catalog.pickerPassages) { passage in
                PassageLibraryRow(passage: passage) {
                    select(passage)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(SpeechScreenBackground())
        .navigationTitle("Passages")
        .navigationBarTitleDisplayMode(.large)
    }

    private func select(_ passage: Passage) {
        model.selectPassage(passage)
    }
}

private struct PassageLibraryRow: View {
    let passage: Passage
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(passage.title)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(passage.durationLabel)
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(passage.title), \(passage.durationLabel)")
    }
}
