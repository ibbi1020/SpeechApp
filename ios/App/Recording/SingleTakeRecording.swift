import Foundation
import OSLog
import SpeechAppKit

/// Saves a one-take recording (Reading, Conversation) after the report opens.
/// Finalizing (denoise, AAC) runs in the background; the report polls the store.
@MainActor
enum SingleTakeRecording {
    private static let log = Logger(subsystem: "com.speechapp", category: "SingleTakeRecording")

    struct Content: Sendable {
        let id: UUID
        let format: RecordingManifest.Format
        let topic: String
        let lines: [MonologueReport.Line]
        let words: [RecordedWord]
        let durationSeconds: TimeInterval
        let markers: [ReviewMarker]
        var partnerTurns: [PartnerTurn]? = nil
        var inLibrary: Bool = true
    }

    /// Finalizes the file beside `makeContent`. Markers and the manifest are
    /// built only after both finish, so the gallery cannot store a transcript
    /// from before the last words arrived.
    static func finalizeAndSave(
        id: UUID,
        rawURL: URL,
        partnerSpans: [PartnerAudioSpan] = [],
        store: RecordingStore = RecordingsService.store,
        makeContent: () async -> Content
    ) async {
        // The report keeps watching until this returns. Leaving the report must not cancel it.
        // Finished is marked only after the manifest write below, or this defer on the way out.
        defer { SaveProgressBoard.markFinished(id: id) }
        // The file work does not need the transcript. It runs while the last words arrive.
        async let finalized = TakeFinalizer.finalizeWithReport(
            rawCAF: rawURL,
            partnerSpans: partnerSpans,
            onProgress: { step, fraction in
                SaveProgressBoard.update(id: id, step, fraction)
            }
        )
        let content = await makeContent()
        do {
            let (finalURL, report) = try await finalized
            try commit(finalURL: finalURL, report: report, content: content, store: store)
        } catch {
            let wall = Int(SaveProgressBoard.wallMilliseconds(id: content.id).rounded())
            log.error("save failed: \(error.localizedDescription, privacy: .public) wall=\(wall)ms")
            try? FileManager.default.removeItem(at: rawURL)
            if TakeRetention.isDiscarded(content.id) { return }
            let outOfSpace = (error as? RecordingStoreError) == .diskFull
            try? store.save(RecordingManifest(
                id: content.id,
                format: content.format,
                topic: content.topic,
                reportLines: content.lines,
                comparison: "",
                takes: [],
                saveError: outOfSpace
                    ? UserFacingFailure.diskFull
                    : UserFacingFailure.nothingToPlay,
                inLibrary: TakeRetention.wantsLibrary(content.id) || content.inLibrary
            ))
        }
    }

    private static func commit(
        finalURL: URL,
        report: TakeFinalizer.Report,
        content: Content,
        store: RecordingStore
    ) throws {
        SaveProgressBoard.update(id: content.id, .writing, 0)
        let fileName = "take-1.m4a"
        _ = try store.storeAudio(regimenID: content.id, from: finalURL, fileName: fileName)
        try? FileManager.default.removeItem(at: finalURL)
        if TakeRetention.isDiscarded(content.id) {
            try? store.delete(id: content.id)
            return
        }
        try store.save(RecordingManifest(
            id: content.id,
            format: content.format,
            topic: content.topic,
            reportLines: content.lines,
            comparison: "",
            takes: [
                RecordingManifest.Take(
                    index: 1,
                    durationSeconds: content.durationSeconds,
                    audioFileName: fileName,
                    words: content.words,
                    markers: content.markers,
                    partnerTurns: content.partnerTurns
                ),
            ],
            inLibrary: TakeRetention.wantsLibrary(content.id) || content.inLibrary
        ))
        SaveProgressBoard.update(id: content.id, .writing, 1)
        let wall = Int(SaveProgressBoard.wallMilliseconds(id: content.id).rounded())
        let line = "\(content.format.rawValue) take saved: \(report.stages.line(usedDenoise: report.usedDenoise)) wall=\(wall)ms markers=\(content.markers.count)"
        log.info("\(line, privacy: .public)")
    }
}
