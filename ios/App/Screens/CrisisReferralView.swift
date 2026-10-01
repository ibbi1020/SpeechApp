import SwiftUI

struct CrisisReferralView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            SpeechScreenBackground()

            VStack(alignment: .leading, spacing: 0) {
                Spacer()

                Text("Call or text 988")
                    .font(.system(.title2, design: .serif).weight(.semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityAddTraits(.isHeader)

                Text("chat 988lifeline.org")
                    .font(.body)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, SpeechSpacing.cluster)

                Text("If you are not in the US, use your local emergency number.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, SpeechSpacing.related)

                Button("Back to home", action: goHome)
                    .buttonStyle(SpeechPrimaryButtonStyle())
                    .padding(.top, 22)

                Spacer()
            }
            .padding(.horizontal, SpeechSpacing.page)
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: pingCrisisIfConfigured)
    }

    private func goHome() {
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : SpeechMotion.settle) {
            model.goHome()
        }
    }

    private func pingCrisisIfConfigured() {
        guard let client = MintClient.makeIfConfigured(uuid: model.account.accountUUID) else {
            return
        }
        Task {
            await client.crisis()
        }
    }
}
