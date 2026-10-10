import SwiftUI
import SpeechAppKit

/// "Listen back" for a saved recording. Shows "Preparing audio…" while the take is
/// still being denoised and written, then the player.
struct RecordingReviewLoader: View {
    let recordingID: UUID?

    @State private var manifest: RecordingManifest?
    @State private var isLoading = false

    var body: some View {
        Group {
            if let manifest {
                TakeReviewSection(manifest: manifest, saveError: manifest.saveError)
            } else if isLoading, let recordingID {
                TakeReviewSection(
                    manifest: RecordingManifest(
                        id: recordingID,
                        topic: "",
                        reportLines: [],
                        comparison: "",
                        takes: []
                    ),
                    saveError: nil
                )
            }
        }
        .task(id: recordingID) {
            await load()
        }
    }

    private func load() async {
        guard let recordingID else { return }
        isLoading = true
        // A conversation can take a couple of minutes to encode after it ends.
        for _ in 0..<480 {
            if let loaded = try? RecordingsService.store.load(id: recordingID) {
                manifest = loaded
                isLoading = false
                return
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
        isLoading = false
    }
}
