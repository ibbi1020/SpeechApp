import SwiftUI

struct ConsentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            SpeechScreenBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("SpeechApp")
                            .font(.largeTitle.weight(.bold))
                            .tracking(-0.6)
                            .accessibilityAddTraits(.isHeader)

                        Text("Private practice for a short passage. Read aloud at your own pace — feedback waits until you stop.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 12)

                    VStack(alignment: .leading, spacing: 14) {
                        ConsentRow(
                            icon: "lock.shield.fill",
                            title: "Stays on this phone",
                            detail: "Listening happens on device for the session."
                        )
                        ConsentRow(
                            icon: "trash.fill",
                            title: "Audio isn’t kept",
                            detail: "Raw recording is discarded when you stop."
                        )
                        ConsentRow(
                            icon: "waveform",
                            title: "Follow-along ≠ sound scoring",
                            detail: "Apple’s listener tracks your place in the text. Fine sound checks use a separate specialized path — coming next."
                        )
                        ConsentRow(
                            icon: "tortoise.fill",
                            title: "No rush",
                            detail: "If you go quiet, you’ll get a gentle nudge — never a pace to chase."
                        )
                    }
                    .padding(18)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(.ultraThinMaterial)
                    )

                    Button("Continue") {
                        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : SpeechMotion.settle) {
                            model.acceptConsent()
                        }
                    }
                    .buttonStyle(SpeechPrimaryButtonStyle())
                    .padding(.top, 4)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
        }
        .navigationBarHidden(true)
    }
}

private struct ConsentRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
