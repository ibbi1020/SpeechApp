import SwiftUI
import SpeechAppKit

/// Chooser opened from the conversation sound button.
struct PartnerVoiceSheet: View {
    let selection: String
    let accountID: UUID
    let onSelect: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var voices = PartnerVoice.catalog

    private var listed: [PartnerVoice] {
        voices.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            List(listed) { voice in
                Button {
                    onSelect(voice.id)
                    dismiss()
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(voice.name)
                                .foregroundStyle(.primary)
                            if !voice.tone.isEmpty {
                                Text(voice.tone)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 8)
                        if voice.id == selection {
                            Image(systemName: "checkmark")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.primary)
                                .accessibilityHidden(true)
                        }
                    }
                }
                .accessibilityLabel(voice.name)
                .accessibilityValue(voice.tone)
                .accessibilityAddTraits(voice.id == selection ? .isSelected : [])
                .buttonStyle(.plain)
            }
            .navigationTitle("Voice")
            .navigationBarTitleDisplayMode(.inline)
            .navigationSubtitle("Starts after this reply")
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task {
            guard let base = MintClient.configuredBase() else { return }
            voices = await PartnerVoiceLoader.fetch(base: base, accountID: accountID)
        }
    }
}
