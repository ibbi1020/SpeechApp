import SwiftUI

struct AgeAttestationView: View {
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
        .navigationTitle("Orator")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { goHome() }
            }
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(CounselCopy.attestation)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button(CounselCopy.attestationButton) {
                withAnimation(reduceMotion ? .easeOut(duration: 0.2) : SpeechMotion.settle) {
                    model.confirmAgeAttestation()
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
