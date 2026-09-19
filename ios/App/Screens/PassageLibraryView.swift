import SwiftUI
import SpeechAppKit

struct PassageLibraryView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            SpeechScreenBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: SpeechSpacing.section) {
                    if let featured = model.featuredPassage {
                        featuredCard(featured)
                    }

                    moreSection
                }
                .padding(.horizontal, SpeechSpacing.page)
                .padding(.top, SpeechSpacing.related)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle("Passages")
        .navigationBarTitleDisplayMode(.large)
    }

    private func featuredCard(_ passage: Passage) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: SpeechSpacing.cluster) {
                Text(passage.title)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(passage.text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.tail)
            }

            Text(passage.durationLabel)
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .padding(.top, SpeechSpacing.related)

            Button("Start") {
                withAnimation(reduceMotion ? .easeOut(duration: 0.2) : SpeechMotion.settle) {
                    model.selectPassage(passage)
                }
            }
            .buttonStyle(SpeechPrimaryButtonStyle())
            .padding(.top, 22)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private var moreSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("More to read")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.6)

            VStack(spacing: 0) {
                ForEach(Array(model.morePassages.enumerated()), id: \.element.id) { index, passage in
                    if index > 0 {
                        Divider()
                            .padding(.leading, 20)
                    }
                    moreRow(passage)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
        }
    }

    private func moreRow(_ passage: Passage) -> some View {
        Button {
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : SpeechMotion.settle) {
                model.selectPassage(passage)
            }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text(passage.title)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 16)
                Text(passage.durationLabel)
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
