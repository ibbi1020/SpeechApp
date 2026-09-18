import SwiftUI
import SpeechAppKit

struct PassageLibraryView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            SpeechScreenBackground()

            List {
                Section {
                    Text("Pick a passage to practice. Longer versions give the follow-along path more to work with.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                }

                ForEach(model.catalog.families, id: \.self) { family in
                    Section(familyTitle(family)) {
                        ForEach(model.catalog.passages(inFamily: family)) { passage in
                            Button {
                                withAnimation(reduceMotion ? .easeOut(duration: 0.2) : SpeechMotion.settle) {
                                    model.selectPassage(passage)
                                }
                            } label: {
                                HStack(alignment: .top, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(passage.title)
                                            .font(.body.weight(.semibold))
                                            .foregroundStyle(.primary)
                                            .multilineTextAlignment(.leading)
                                        Text("\(passage.wordCount) words · ~\(passage.estimatedSeconds)s · \(passage.length.label)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        if !passage.contrastTags.isEmpty {
                                            Text(passage.contrastTags.joined(separator: " · "))
                                                .font(.caption2)
                                                .foregroundStyle(.tertiary)
                                                .lineLimit(1)
                                        }
                                    }
                                    Spacer(minLength: 8)
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Passages")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Suggested") {
                    withAnimation(reduceMotion ? .easeOut(duration: 0.2) : SpeechMotion.settle) {
                        model.beginSuggestedReading()
                    }
                }
            }
        }
    }

    private func familyTitle(_ family: String) -> String {
        family
            .replacingOccurrences(of: "-", with: " / ")
            .replacingOccurrences(of: "ae", with: "æ")
            .capitalized
    }
}
