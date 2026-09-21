import SwiftUI

struct CrisisReferralView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            SpeechScreenBackground()

            VStack(alignment: .leading, spacing: 0) {
                Spacer()

                Text("Crisis")
                    .font(.system(.title2, design: .serif).weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button("Done") {
                    withAnimation(reduceMotion ? .easeOut(duration: 0.2) : SpeechMotion.settle) {
                        model.goHome()
                    }
                }
                .buttonStyle(SpeechPrimaryButtonStyle())
                .padding(.top, 22)

                Spacer()
            }
            .padding(.horizontal, SpeechSpacing.page)
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}
