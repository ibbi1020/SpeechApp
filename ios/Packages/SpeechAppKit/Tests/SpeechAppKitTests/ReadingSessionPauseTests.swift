import Foundation
import Testing
@testable import SpeechAppKit

@Suite("ReadingSession pause")
struct ReadingSessionPauseTests {
    @Test("durationSeconds counts running intervals only")
    @MainActor
    func durationExcludesPausedWallClock() async throws {
        let session = ReadingSession(passage: Self.harnessPassage, stallTimeout: 30)
        let source = ControllableAudioSource()
        let engine = ScriptedTranscriptEngine(words: [], wordInterval: 1, emitVolatiles: false)

        try await session.start(audioSource: source, engine: engine)
        try await Task.sleep(for: .milliseconds(180))
        session.pause()
        #expect(session.phase == .paused)

        try await Task.sleep(for: .milliseconds(450))
        session.resume()
        #expect(session.phase == .running)

        try await Task.sleep(for: .milliseconds(180))
        let report = await session.stop()

        #expect(report.durationSeconds > 0.2)
        #expect(report.durationSeconds < 0.55)
    }

    @Test("paused chunks are omitted from PCM capture")
    @MainActor
    func pauseSkipsPCM() async throws {
        let session = ReadingSession(passage: Self.harnessPassage, stallTimeout: 30)
        let source = ControllableAudioSource()
        let engine = ScriptedTranscriptEngine(words: [], wordInterval: 1, emitVolatiles: false)

        try await session.start(audioSource: source, engine: engine)
        source.yield(seconds: 1)
        try await Task.sleep(for: .milliseconds(40))

        session.pause()
        source.yield(seconds: 2)
        try await Task.sleep(for: .milliseconds(40))

        session.resume()
        source.yield(seconds: 1)
        try await Task.sleep(for: .milliseconds(40))

        let report = await session.stop()
        #expect(report.pcmCapturedSeconds > 1.5)
        #expect(report.pcmCapturedSeconds < 2.5)
    }

    @Test("occupancy is unchanged across pause")
    @MainActor
    func occupancyFrozenWhilePaused() async throws {
        let passage = Self.harnessPassage
        let session = ReadingSession(passage: passage, stallTimeout: 30)
        let source = ControllableAudioSource()
        let engine = ScriptedTranscriptEngine(
            words: passage.words.map(\.surface),
            wordInterval: 0.08,
            emitVolatiles: true
        )

        try await session.start(audioSource: source, engine: engine)
        try await Task.sleep(for: .milliseconds(120))
        session.pause()

        let heardAtPause = session.heardWordIDs
        #expect(!heardAtPause.isEmpty)

        await engine.waitUntilFinished()
        try await Task.sleep(for: .milliseconds(80))
        #expect(session.heardWordIDs == heardAtPause)

        session.resume()
        #expect(session.heardWordIDs == heardAtPause)

        _ = await session.stop()
    }

    private static let harnessPassage = Passage(
        id: "pause-harness",
        title: "Pause",
        words: [
            ScriptWord(id: "w0", surface: "the"),
            ScriptWord(id: "w1", surface: "quick"),
            ScriptWord(id: "w2", surface: "brown"),
            ScriptWord(id: "w3", surface: "fox"),
            ScriptWord(id: "w4", surface: "jumps"),
        ]
    )
}

final class ControllableAudioSource: AudioSource, @unchecked Sendable {
    let chunks: AsyncStream<AudioChunk>
    private let continuation: AsyncStream<AudioChunk>.Continuation

    init() {
        let pair = AsyncStream<AudioChunk>.makeStream(bufferingPolicy: .unbounded)
        chunks = pair.stream
        continuation = pair.continuation
    }

    func start() async throws {}

    func stop() async {
        continuation.finish()
    }

    func yield(seconds: Double, amplitude: Float = 0.2, sampleRate: Double = 16_000) {
        let count = max(1, Int(seconds * sampleRate))
        continuation.yield(
            AudioChunk(
                samples: Array(repeating: amplitude, count: count),
                sampleRate: sampleRate,
                hostTime: 0
            )
        )
    }
}
