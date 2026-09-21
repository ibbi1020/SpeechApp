import SwiftUI
import SpeechAppKit

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            SpeechScreenBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: SpeechSpacing.section) {
                    conversationCard

                    readSection
                }
                .padding(.horizontal, SpeechSpacing.page)
                .padding(.top, SpeechSpacing.related)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle("SpeechApp")
        .navigationBarTitleDisplayMode(.large)
    }

    private var conversationCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: SpeechSpacing.cluster) {
                Text("Start a conversation")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("AI partner")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Text(model.budget.label)
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .padding(.top, SpeechSpacing.related)

            Button("Start a conversation") {
                withAnimation(reduceMotion ? .easeOut(duration: 0.2) : SpeechMotion.settle) {
                    model.requestStartConversation()
                }
            }
            .buttonStyle(SpeechPrimaryButtonStyle())
            .disabled(!model.budget.startEnabled)
            .opacity(model.budget.startEnabled ? 1 : 0.45)
            .padding(.top, 22)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private var readSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("More to read")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.6)

            Button {
                withAnimation(reduceMotion ? .easeOut(duration: 0.2) : SpeechMotion.settle) {
                    model.route = .library
                }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    Text("Read a passage")
                        .font(.body)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 16)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
        }
    }
}
