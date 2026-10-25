import Foundation
import Testing
@testable import SpeechAppKit

@Suite("Reading finish")
struct ReadingFinishTests {
    @Test("a full live hypothesis moves the underline to the last word")
    @MainActor
    func fullHypothesisReachesLastWord() async throws {
        let passage = Passage(
            id: "tail",
            title: "Tail",
            words: [
                ScriptWord(id: "w0", surface: "the"),
                ScriptWord(id: "w1", surface: "quick"),
                ScriptWord(id: "w2", surface: "brown"),
                ScriptWord(id: "w3", surface: "fox"),
            ]
        )
        let session = ReadingSession(passage: passage, stallTimeout: 30)
        let url = try #require(Bundle.module.url(forResource: "silence", withExtension: "wav"))
        let source = FileReplayAudioSource(fileURL: url, chunkDuration: 0.05)
        let engine = OneHypothesisEngine(surfaces: passage.words.map(\.surface))
        try await session.start(audioSource: source, engine: engine)
        await engine.waitUntilFinished()
        try await Task.sleep(for: .milliseconds(50))
        #expect(session.caretAnchor.index == passage.words.count - 1)
        _ = await session.stop()
    }
}

/// One volatile hypothesis and no finals, so the committed cursor stays behind.
private final class OneHypothesisEngine: TranscriptionEngine, @unchecked Sendable {
    let surfaces: [String]
    private var updateContinuation: AsyncStream<TranscriptionUpdate>.Continuation?
    private var finishedContinuation: CheckedContinuation<Void, Never>?
    private var didFinish = false

    init(surfaces: [String]) {
        self.surfaces = surfaces
    }

    var engineKind: LiveTranscriptionEngine.EngineKind { .grokVoiceTranscribe }

    var updates: AsyncStream<TranscriptionUpdate> {
        let pair = AsyncStream<TranscriptionUpdate>.makeStream(bufferingPolicy: .bufferingNewest(8))
        updateContinuation = pair.continuation
        return pair.stream
    }

    func setContextualPhrases(_ phrases: [String]) {}

    func prepareIfNeeded(locale: Locale) async throws {}

    func start(
        locale: Locale,
        preference: LiveTranscriptionEngine.EnginePreference
    ) async throws {
        let tokens = surfaces.map { SpokenToken(surface: $0, isFinal: false) }
        updateContinuation?.yield(
            TranscriptionUpdate(
                tokens: tokens,
                engineKind: .grokVoiceTranscribe,
                rawText: surfaces.joined(separator: " ")
            )
        )
        markFinished()
    }

    func append(_ chunk: AudioChunk) {}

    func stop() async {
        updateContinuation?.finish()
        markFinished()
    }

    func waitUntilFinished() async {
        if didFinish { return }
        await withCheckedContinuation { continuation in
            finishedContinuation = continuation
        }
    }

    private func markFinished() {
        guard !didFinish else { return }
        didFinish = true
        finishedContinuation?.resume()
        finishedContinuation = nil
    }
}
