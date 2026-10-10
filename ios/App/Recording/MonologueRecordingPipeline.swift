import Foundation
import SpeechAppKit

/// Builds a saved regimen from finished takes + the fluency report.
@MainActor
enum MonologueRecordingPipeline {
    struct FinishedTake: Sendable {
        let index: Int
        let durationSeconds: TimeInterval
        let words: [RecordedWord]
        let audioURL: URL
    }

    static func save(
        regimenID: UUID,
        topic: String,
        report: MonologueReport,
        finishedTakes: [FinishedTake],
        store: RecordingStore = RecordingsService.store
    ) throws -> RecordingManifest {
        var takeEntries: [RecordingManifest.Take] = []
        for finished in finishedTakes {
            let fileName = "take-\(finished.index).m4a"
            _ = try store.storeAudio(regimenID: regimenID, from: finished.audioURL, fileName: fileName)
            let markers = ReviewMarkers.build(
                words: finished.words,
                durationSeconds: finished.durationSeconds
            )
            takeEntries.append(
                RecordingManifest.Take(
                    index: finished.index,
                    durationSeconds: finished.durationSeconds,
                    audioFileName: fileName,
                    words: finished.words,
                    markers: markers
                )
            )
            try? FileManager.default.removeItem(at: finished.audioURL)
        }

        let manifest = RecordingManifest(
            id: regimenID,
            format: .monologue,
            topic: topic,
            reportLines: report.lines,
            comparison: report.comparison,
            takes: takeEntries
        )
        try store.save(manifest)
        return manifest
    }

    static func saveDiskFullPlaceholder(
        regimenID: UUID,
        topic: String,
        report: MonologueReport,
        store: RecordingStore = RecordingsService.store
    ) throws {
        let manifest = RecordingManifest(
            id: regimenID,
            format: .monologue,
            topic: topic,
            reportLines: report.lines,
            comparison: report.comparison,
            takes: [],
            saveError: "Couldn't save this recording. Your phone is out of space."
        )
        try store.save(manifest)
    }
}
