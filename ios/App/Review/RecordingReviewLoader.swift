import SwiftUI
import SpeechAppKit

/// Shown in the feedback slot while a take is still being saved, and when it never arrives.
struct FeedbackPreparing: View {
    var message: String
    var detail: String? = nil
    /// How full the ring is, from 0 to 1. Nil hides the ring.
    var progress: Double? = nil

    var body: some View {
        VStack(spacing: SpeechSpacing.related) {
            if let progress {
                SaveProgressRing(progress: progress)
                    .accessibilityLabel("Progress")
                    .accessibilityValue("\(Int((min(1, max(0, progress)) * 100).rounded())) percent")
            }
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let detail {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, SpeechSpacing.section)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// A ring that fills only as far as `progress`. It does not spin.
private struct SaveProgressRing: View {
    var progress: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.35), lineWidth: 3)
            Circle()
                .trim(from: 0, to: CGFloat(min(1, max(0, progress))))
                .stroke(Color.primary, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 44, height: 44)
        .animation(reduceMotion ? nil : .linear(duration: 0.25), value: progress)
    }
}

/// "Listen back" for a saved recording. Shows the save ring while the take is
/// still being written, then the player. A slow save is not a failure.
struct RecordingReviewLoader: View {
    let recordingID: UUID?

    @State private var manifest: RecordingManifest?
    @State private var gaveUp = false
    @State private var fraction: Double = 0
    @State private var message = "Saving your take"
    @State private var detail: String?

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
                FeedbackPreparing(message: "This take didn't come through.")
            } else {
                FeedbackPreparing(message: message, detail: detail, progress: fraction)
            }
        }
        .task(id: recordingID) {
            await watch()
        }
    }

    private func watch() async {
        guard manifest == nil, let recordingID else { return }
        var lastFraction = 0.0
        var unchangedSince = Date()
        while !Task.isCancelled {
            if let loaded = Self.ready(recordingID) {
                manifest = loaded
                return
            }
            let snapshot = SaveProgressBoard.snapshot(id: recordingID)
            if snapshot?.finished == true {
                if let loaded = Self.ready(recordingID) {
                    manifest = loaded
                } else {
                    gaveUp = true
                }
                return
            }
            let shown = snapshot?.progress.displayedFraction(ready: false) ?? 0
            let stepSentence = snapshot?.progress.step.sentence ?? "Saving your take"
            if shown != lastFraction {
                lastFraction = shown
                unchangedSince = Date()
            }
            fraction = shown
            let stalled = Date().timeIntervalSince(unchangedSince)
            if SaveProgress.showsStillSaving(unchangedFor: stalled) {
                message = SaveProgress.stillSavingLine
            } else {
                message = stepSentence
            }
            detail = SaveProgress.showsSlowLine(unchangedFor: stalled) ? SaveProgress.slowLine : nil
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

    /// A manifest counts once it has audio, or a real save error.
    private static func ready(_ id: UUID) -> RecordingManifest? {
        guard let loaded = try? RecordingsService.store.load(id: id) else { return nil }
        guard !loaded.takes.isEmpty || loaded.saveError != nil else { return nil }
        return loaded
    }
}
