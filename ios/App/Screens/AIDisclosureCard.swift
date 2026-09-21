import SwiftUI

struct AIDisclosureCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            SpeechScreenBackground()

            VStack {
                Spacer()
                card
                Spacer()
            }
            .padding(.horizontal, SpeechSpacing.page)
        }
        .navigationTitle("Conversation")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { goHome() }
            }
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: SpeechSpacing.cluster) {
                Text("AI partner")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Text(CounselCopy.disclosure)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button("Start a conversation") {
                withAnimation(reduceMotion ? .easeOut(duration: 0.2) : SpeechMotion.settle) {
                    model.confirmAIDisclosure()
                }
            }
            .buttonStyle(SpeechPrimaryButtonStyle())
            .padding(.top, 22)

            Button("Cancel") { goHome() }
                .buttonStyle(SpeechSecondaryButtonStyle())
                .padding(.top, 10)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func goHome() {
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : SpeechMotion.settle) {
            model.goHome()
        }
    }
}
