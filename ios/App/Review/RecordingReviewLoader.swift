import SwiftUI
import SpeechAppKit

/// Shown in the feedback slot while a take is still being saved, and when it never arrives.
struct FeedbackPreparing: View {
    var message: String
    var showsSpinner: Bool = true

    var body: some View {
        VStack(spacing: SpeechSpacing.related) {
            if showsSpinner {
                ProgressView()
            }
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, SpeechSpacing.section)
        .accessibilityElement(children: .combine)
    }
}

/// "Listen back" for a saved recording. Shows a spinner while the take is
/// still being denoised and written, then the player.
struct RecordingReviewLoader: View {
    let recordingID: UUID?

    @State private var manifest: RecordingManifest?
    @State private var gaveUp = false

    init(recordingID: UUID?) {
        self.recordingID = recordingID
        if let recordingID, let loaded = Self.ready(recordingID) {
            _manifest = State(initialValue: loaded)
        }
    }

    var body: some View {
        Group {
            if let manifest {
                TakeReviewSection(manifest: manifest, saveError: manifest.saveError)
            } else if gaveUp {
                FeedbackPreparing(message: "This take didn't come through.", showsSpinner: false)
            } else {
                FeedbackPreparing(message: "Preparing your feedback")
            }
        }
        .task(id: recordingID) {
            await load()
        }
    }

    private func load() async {
        guard manifest == nil, let recordingID else { return }
        // A conversation can take a couple of minutes to encode after it ends.
        for _ in 0..<480 {
            if Task.isCancelled { return }
            if let loaded = Self.ready(recordingID) {
                manifest = loaded
                return
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
        gaveUp = true
    }

    /// A manifest counts once it has audio, or a real save error.
    private static func ready(_ id: UUID) -> RecordingManifest? {
        guard let loaded = try? RecordingsService.store.load(id: id) else { return nil }
        guard !loaded.takes.isEmpty || loaded.saveError != nil else { return nil }
        return loaded
    }
}
