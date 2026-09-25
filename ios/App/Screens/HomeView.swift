import SwiftUI
import SpeechAppKit

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            SpeechScreenBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    formatRow(title: "Read a passage") {
                        model.route = .library
                    }
                    formatRow(
                        title: "Start a conversation",
                        footnote: model.budget.label,
                        disabled: !model.budget.startEnabled
                    ) {
                        model.requestStartConversation()
                    }
                    formatRow(title: "Talk about something") {
                        model.requestStartMonologue()
                    }
                }
                .padding(.horizontal, SpeechSpacing.page)
                .padding(.top, SpeechSpacing.related)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle("Orator")
        .navigationBarTitleDisplayMode(.large)
    }

    private func formatRow(
        title: String,
        footnote: String? = nil,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : SpeechMotion.settle) {
                action()
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if let footnote {
                    Text(footnote)
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 22))
    }
}
