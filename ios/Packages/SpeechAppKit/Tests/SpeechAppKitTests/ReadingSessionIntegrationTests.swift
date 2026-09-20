import Foundation
import Testing
@testable import SpeechAppKit

@Suite("ReadingSession integration")
struct ReadingSessionIntegrationTests {
    @Test("aligns injected spoken tokens into a report")
    @MainActor
    func injectedTokensProduceReport() async throws {
        let passage = PassageCatalog.fallbackPassages[0]
        let aligner = TokenAligner(passage: passage)
        for word in passage.words.prefix(3) {
            _ = aligner.ingest(SpokenToken(surface: word.surface, isFinal: true))
        }
        let marks = aligner.liveMarks()
        #expect(marks.isEmpty)
        #expect(aligner.scriptCursor == 3)

        // Stall detector still works on quiet/loud chunks from scripted source
        let detector = StallDetector(configuration: .init(silenceTimeout: 0.5))
        _ = detector.process(samples: Array(repeating: 0.2, count: 100), at: 0)
        #expect(detector.process(samples: Array(repeating: 0, count: 100), at: 0.6) == true)
    }

    @Test("FileReplay + ScriptedTranscriptEngine starts ReadingSession and gates occupancy")
    @MainActor
    func fileReplayOccupancyHarness() async throws {
        let passage = Passage(
            id: "harness",
            title: "Harness",
            words: [
                ScriptWord(id: "w0", surface: "the"),
                ScriptWord(id: "w1", surface: "quick"),
                ScriptWord(id: "w2", surface: "brown"),
                ScriptWord(id: "w3", surface: "fox"),
            ]
        )
        let session = ReadingSession(passage: passage, stallTimeout: 30)
        let url = Bundle.module.url(forResource: "silence", withExtension: "wav")
        #expect(url != nil)
        guard let url else { return }

        let source = FileReplayAudioSource(fileURL: url, chunkDuration: 0.05)
        let engine = ScriptedTranscriptEngine(
            words: passage.words.map(\.surface),
            wordInterval: 0.05,
            emitVolatiles: true
        )

        try await session.start(audioSource: source, engine: engine)
        await engine.waitUntilFinished()
        // Brief drain for volatile→final handling on MainActor.
        try await Task.sleep(for: .milliseconds(50))

        let report = await session.stop()
        let occupancy = Double(report.matchCount) / Double(passage.words.count)
        #expect(report.matchCount == passage.words.count)
        #expect(report.skipCount == 0)
        #expect(occupancy >= 0.99)
        // Device p99 remains a human/device gate; harness proves the session path.
        #expect(session.volatileCaretLatencies.count + session.finalCaretLatencies.count >= 1)
        #expect(session.liveSkipMarks.isEmpty)
    }

    @Test("skip and insert show up as live marks")
    func skipAndInsertMarks() {
        let passage = Passage(
            id: "t",
            title: "T",
            words: [
                ScriptWord(id: "a", surface: "one"),
                ScriptWord(id: "b", surface: "two"),
                ScriptWord(id: "c", surface: "three"),
            ]
        )
        let aligner = TokenAligner(passage: passage)
        _ = aligner.ingest(SpokenToken(surface: "two", isFinal: true))
        _ = aligner.ingest(SpokenToken(surface: "three", isFinal: true))
        _ = aligner.ingest(SpokenToken(surface: "bonus", isFinal: true))
        let kinds = aligner.liveMarks().map(\.kind)
        #expect(kinds == [.extra])
    }

    @Test("FileReplayAudioSource streams bundled silence WAV")
    func fileReplaySilence() async throws {
        let url = Bundle.module.url(forResource: "silence", withExtension: "wav")
        #expect(url != nil)
        guard let url else { return }
        let source = FileReplayAudioSource(fileURL: url, chunkDuration: 0.05)
        let counter = ChunkCounter()
        let consumer = Task {
            for await _ in source.chunks {
                await counter.increment()
            }
        }
        try await source.start()
        await consumer.value
        let count = await counter.value
        #expect(count > 0)
        await source.stop()
    }
}

actor ChunkCounter {
    private(set) var value = 0
    func increment() { value += 1 }
}

/// Emits quiet PCM then finishes — used to prove FileReplay-shaped sources compile in tests.
final class ScriptedAudioSource: AudioSource, @unchecked Sendable {
    let chunks: AsyncStream<AudioChunk>
    private let continuation: AsyncStream<AudioChunk>.Continuation
    private let spokenWords: [String]
    private let sampleRate: Double

    init(spokenWords: [String], sampleRate: Double) {
        self.spokenWords = spokenWords
        self.sampleRate = sampleRate
        let pair = AsyncStream<AudioChunk>.makeStream()
        chunks = pair.stream
        continuation = pair.continuation
    }

    func start() async throws {
        for (index, _) in spokenWords.enumerated() {
            let samples = Array(repeating: Float(0.05), count: 800)
            continuation.yield(
                AudioChunk(samples: samples, sampleRate: sampleRate, hostTime: Double(index) * 0.2)
            )
        }
        continuation.finish()
    }

    func stop() async {
        continuation.finish()
    }
}
