import SwiftUI
import SpeechAppKit

struct HomeView: View {
    @Environment(AppModel.self) private var model

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
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.body)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
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
