import Foundation
import SpeechAppKit

/// The person left the report without Save. The manifest must not be written.
struct DiscardedTake: Error {}

/// Builds a saved regimen from finished takes + the fluency report.
@MainActor
enum MonologueRecordingPipeline {
    struct FinishedTake: Sendable {
        let index: Int
        let durationSeconds: TimeInterval
        let words: [RecordedWord]
        let audioURL: URL
    }

    /// Writes every take that did save. One failed take must not wipe the others.
    /// Leaving without Save deletes the folder instead of writing a manifest.
    static func persist(
        regimenID: UUID,
        topic: String,
        report: MonologueReport,
        finishedTakes: [FinishedTake],
        inLibrary: Bool,
        saveError: String?,
        onWriting: ((Double) -> Void)? = nil
    ) {
        do {
            if TakeRetention.isDiscarded(regimenID) {
                try? RecordingsService.store.delete(id: regimenID)
                return
            }
            if !finishedTakes.isEmpty {
                _ = try save(
                    regimenID: regimenID,
                    topic: topic,
                    report: report,
                    finishedTakes: finishedTakes,
                    inLibrary: inLibrary,
                    onWriting: onWriting
                )
            } else if inLibrary, let saveError {
                try saveFailurePlaceholder(
                    regimenID: regimenID,
                    topic: topic,
                    report: report,
                    saveError: saveError
                )
            }
        } catch is DiscardedTake {
            return
        } catch RecordingStoreError.diskFull where inLibrary {
            try? saveDiskFullPlaceholder(
                regimenID: regimenID,
                topic: topic,
                report: report
            )
        } catch {
            // Report still shows; the player stays empty until a manifest exists.
        }
    }

    static func save(
        regimenID: UUID,
        topic: String,
        report: MonologueReport,
        finishedTakes: [FinishedTake],
        inLibrary: Bool = true,
        store: RecordingStore = RecordingsService.store,
        onWriting: ((Double) -> Void)? = nil
    ) throws -> RecordingManifest {
        var takeEntries: [RecordingManifest.Take] = []
        let total = Double(finishedTakes.count)
        onWriting?(0)
        for (offset, finished) in finishedTakes.enumerated() {
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
            if total > 0 {
                onWriting?(Double(offset + 1) / total)
            }
        }

        if TakeRetention.isDiscarded(regimenID) {
            try? store.delete(id: regimenID)
            throw DiscardedTake()
        }

        let manifest = RecordingManifest(
            id: regimenID,
            format: .monologue,
            topic: topic,
            reportLines: report.lines,
            comparison: report.comparison,
            takes: takeEntries,
            inLibrary: TakeRetention.wantsLibrary(regimenID) || inLibrary
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
        try saveFailurePlaceholder(
            regimenID: regimenID,
            topic: topic,
            report: report,
            saveError: UserFacingFailure.diskFull,
            store: store
        )
    }

    /// Saves the report with no audio, and the sentence the person should see.
    static func saveFailurePlaceholder(
        regimenID: UUID,
        topic: String,
        report: MonologueReport,
        saveError: String,
        store: RecordingStore = RecordingsService.store
    ) throws {
        if TakeRetention.isDiscarded(regimenID) {
            try? store.delete(id: regimenID)
            throw DiscardedTake()
        }
        let manifest = RecordingManifest(
            id: regimenID,
            format: .monologue,
            topic: topic,
            reportLines: report.lines,
            comparison: report.comparison,
            takes: [],
            saveError: saveError
        )
        try store.save(manifest)
    }
}
