import Foundation
import Testing
@testable import SpeechAppKit

@Suite("SessionDiagnostics")
struct SessionDiagnosticsTests {
    @Test("freeze requires sustained speech and high fill")
    func freezeThresholds() {
        #expect(
            SessionDiagnostics.shouldEmitFreeze(
                speakingDuration: 0.5,
                fill: 0.95,
                alreadyEmittedForThisCaret: false
            ) == false
        )
        #expect(
            SessionDiagnostics.shouldEmitFreeze(
                speakingDuration: 0.8,
                fill: 0.85,
                alreadyEmittedForThisCaret: false
            ) == false
        )
        #expect(
            SessionDiagnostics.shouldEmitFreeze(
                speakingDuration: 0.8,
                fill: 0.9,
                alreadyEmittedForThisCaret: false
            ) == true
        )
        #expect(
            SessionDiagnostics.shouldEmitFreeze(
                speakingDuration: 1.5,
                fill: 0.95,
                alreadyEmittedForThisCaret: true
            ) == false
        )
    }

    @Test("burst only after silence with enough tokens")
    func burstThresholds() {
        #expect(
            SessionDiagnostics.shouldEmitBurst(
                tokenTimestampsInWindow: 4,
                wasSilentBeforeBurst: false
            ) == false
        )
        #expect(
            SessionDiagnostics.shouldEmitBurst(
                tokenTimestampsInWindow: 3,
                wasSilentBeforeBurst: true
            ) == false
        )
        #expect(
            SessionDiagnostics.shouldEmitBurst(
                tokenTimestampsInWindow: 4,
                wasSilentBeforeBurst: true
            ) == true
        )
    }

    @Test("writes a JSONL session file under Documents")
    func writesLogFile() throws {
        let diag = SessionDiagnostics(passageID: "test-passage")
        diag.noteChunk(
            handleDuration: 0.002,
            speaking: true,
            rmsEnergy: 0.4,
            fill: 0.5,
            currentWordID: "w0"
        )
        diag.noteASRUpdate(
            engineKind: "speechTranscriber",
            finalCount: 0,
            volatileCount: 2,
            caretBefore: "w0",
            caretAfter: "w0",
            wasSpeaking: true
        )
        let url = diag.finishSummary(volatileLatencies: [0.2, 0.3], finalLatencies: [0.4])
        #expect(url != nil)
        let path = try #require(url?.path)
        #expect(FileManager.default.fileExists(atPath: path))
        let text = try String(contentsOfFile: path, encoding: .utf8)
        #expect(text.contains("\"event\":\"session_start\""))
        #expect(text.contains("\"event\":\"chunk\""))
        #expect(text.contains("\"event\":\"asr_update\""))
        #expect(text.contains("\"event\":\"summary\""))
        try? FileManager.default.removeItem(atPath: path)
    }
}
