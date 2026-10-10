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
    }

    static func finalizeAndSave(rawURL: URL, content: Content, store: RecordingStore = RecordingsService.store) {
        Task { @MainActor in
            do {
                let (finalURL, report) = try await TakeFinalizer.finalizeWithReport(rawCAF: rawURL)
                log.info(
                    "\(content.format.rawValue, privacy: .public) take saved: denoise=\(report.usedDenoise) gain=\(report.gain) outputPeak=\(report.outputPeak) markers=\(content.markers.count)"
                )
                let fileName = "take-1.m4a"
                _ = try store.storeAudio(regimenID: content.id, from: finalURL, fileName: fileName)
                try? FileManager.default.removeItem(at: finalURL)
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
                    ]
                ))
            } catch TakeFinalizerError.empty {
                try? FileManager.default.removeItem(at: rawURL)
            } catch {
                log.error("save failed: \(error.localizedDescription, privacy: .public)")
                try? FileManager.default.removeItem(at: rawURL)
                try? store.save(RecordingManifest(
                    id: content.id,
                    format: content.format,
                    topic: content.topic,
                    reportLines: content.lines,
                    comparison: "",
                    takes: [],
                    saveError: "Couldn't save this recording. Your phone is out of space."
                ))
            }
        }
    }
}
