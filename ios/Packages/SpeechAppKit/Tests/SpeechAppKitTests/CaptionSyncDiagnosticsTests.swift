import Foundation
import Testing
@testable import SpeechAppKit

@Suite("CaptionSyncDiagnostics")
struct CaptionSyncDiagnosticsTests {
    @Test("writes a JSONL caption-sync file under Documents")
    func writesLogFile() throws {
        let diag = CaptionSyncDiagnostics(conversationID: "test-convo")
        diag.noteResponseCreated()
        diag.noteAudioDelta(
            deltaFrames: 2_400,
            queuedFrames: 2_400,
            completedFrames: 0,
            pendingWords: 0,
            revealedWords: 0
        )
        diag.noteTranscriptDelta(
            deltaChars: 5,
            queuedFrames: 2_400,
            completedFrames: 0,
            pendingWords: 1,
            revealedWords: 0
        )
        diag.noteAudioComplete(
            deltaFrames: 2_400,
            queuedFrames: 2_400,
            completedFrames: 2_400,
            pendingWords: 1,
            revealedWordsBefore: 0,
            revealedWordsAfter: 1,
            yielded: true,
            preview: "Hello"
        )
        diag.noteCaptionYield(
            revealedWords: 1,
            pendingWords: 1,
            queuedFrames: 2_400,
            completedFrames: 2_400,
            preview: "Hello"
        )
        let url = diag.finish()
        #expect(url != nil)
        let path = try #require(url?.path)
        #expect(FileManager.default.fileExists(atPath: path))
        let text = try String(contentsOfFile: path, encoding: .utf8)
        #expect(text.contains("\"event\":\"session_start\""))
        #expect(text.contains("\"event\":\"audio_delta\""))
        #expect(text.contains("\"event\":\"caption_yield\""))
        #expect(text.contains("\"event\":\"session_end\""))
        #expect(text.contains("[CaptionSync]") == false)
    }

    @Test("preview keeps the trailing characters")
    func previewTail() {
        let long = String(repeating: "a", count: 50)
        let preview = CaptionSyncDiagnostics.preview(long, limit: 40)
        #expect(preview.count == 40)
        #expect(preview == String(long.suffix(40)))
    }
}
