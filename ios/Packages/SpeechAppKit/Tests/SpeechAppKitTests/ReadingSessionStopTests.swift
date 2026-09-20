import Foundation
import Testing
@testable import SpeechAppKit

@Suite("ReadingSession stop drain")
struct ReadingSessionStopTests {
    @Test("stop freezes duration but drains remaining finals before the report")
    @MainActor
    func stopDrainsQueuedFinals() async throws {
        let passage = Self.passage
        let session = ReadingSession(passage: passage, stallTimeout: 30)
        let source = ControllableAudioSource()
        let engine = GatedTranscriptEngine(
            prefix: ["the", "quick", "brown"],
            suffix: ["fox", "jumps"]
        )

        try await session.start(audioSource: source, engine: engine)
        await engine.waitUntilPrefixEmitted()
        try await Task.sleep(for: .milliseconds(40))

        let report = await session.stop()
        #expect(report.matchCount == 5)
        #expect(report.skipCount == 0)
        #expect(engine.didEmitSuffix)
    }

    @Test("stop duration excludes finishing drain time")
    @MainActor
    func stopDurationExcludesDrain() async throws {
        let session = ReadingSession(passage: Self.passage, stallTimeout: 30)
        let source = ControllableAudioSource()
        let engine = GatedTranscriptEngine(
            prefix: ["the", "quick"],
            suffix: ["brown", "fox", "jumps"],
            suffixDelay: 0.35
        )

        try await session.start(audioSource: source, engine: engine)
        await engine.waitUntilPrefixEmitted()
        try await Task.sleep(for: .milliseconds(50))

        let report = await session.stop()
        #expect(report.durationSeconds < 0.35)
        #expect(report.matchCount == 5)
    }

    @Test("a short late final does not wipe a longer volatile tail on stop")
    @MainActor
    func shortFinalDoesNotWipeVolatileTail() async throws {
        let passage = Self.passage
        let session = ReadingSession(passage: passage, stallTimeout: 30)
        let source = ControllableAudioSource()
        let engine = HypothesisWipeEngine(
            committed: ["the", "quick", "brown"],
            volatileTail: ["the", "quick", "brown", "fox", "jumps"],
            shortFinal: "the quick"
        )

        try await session.start(audioSource: source, engine: engine)
        await engine.waitUntilReadyToStop()
        try await Task.sleep(for: .milliseconds(40))

        let report = await session.stop()
        #expect(report.matchCount == 5)
        #expect(report.skipCount == 0)
    }

    private static let passage = Passage(
        id: "stop-drain",
        title: "Drain",
        words: [
            ScriptWord(id: "w0", surface: "the"),
            ScriptWord(id: "w1", surface: "quick"),
            ScriptWord(id: "w2", surface: "brown"),
            ScriptWord(id: "w3", surface: "fox"),
            ScriptWord(id: "w4", surface: "jumps"),
        ]
    )
}

/// Emits a prefix, waits for `stop()`, then emits remaining finals (Apple finalize).
final class GatedTranscriptEngine: TranscriptionEngine, @unchecked Sendable {
    var engineKind: LiveTranscriptionEngine.EngineKind = .speechTranscriber
    let prefix: [String]
    let suffix: [String]
    let suffixDelay: TimeInterval
    private(set) var didEmitSuffix = false

    private var updateContinuation: AsyncStream<TranscriptionUpdate>.Continuation?
    private let prefixEmitted = Latch()
    private let stopRequested = Latch()
    private let drained = Latch()
    private var emitTask: Task<Void, Never>?

    init(prefix: [String], suffix: [String], suffixDelay: TimeInterval = 0.04) {
        self.prefix = prefix
        self.suffix = suffix
        self.suffixDelay = suffixDelay
    }

    var updates: AsyncStream<TranscriptionUpdate> {
        let pair = AsyncStream<TranscriptionUpdate>.makeStream(bufferingPolicy: .unbounded)
        updateContinuation = pair.continuation
        return pair.stream
    }

    func setContextualPhrases(_ phrases: [String]) { _ = phrases }
    func prepareIfNeeded(locale: Locale) async throws { _ = locale }
    func append(_ chunk: AudioChunk) { _ = chunk }

    func start(
        locale: Locale,
        preference: LiveTranscriptionEngine.EnginePreference
    ) async throws {
        _ = locale
        _ = preference
        emitTask = Task { [weak self] in
            guard let self else { return }
            var cumulative: [String] = []
            for word in self.prefix {
                cumulative.append(word)
                self.yield(
                    tokens: [SpokenToken(surface: word, isFinal: true)],
                    rawText: cumulative.joined(separator: " ")
                )
            }
            self.prefixEmitted.open()
            await self.stopRequested.wait()
            if self.suffixDelay > 0 {
                try? await Task.sleep(for: .seconds(self.suffixDelay))
            }
            for word in self.suffix {
                cumulative.append(word)
                self.yield(
                    tokens: [SpokenToken(surface: word, isFinal: true)],
                    rawText: cumulative.joined(separator: " ")
                )
            }
            self.didEmitSuffix = true
            self.updateContinuation?.finish()
            self.updateContinuation = nil
            self.drained.open()
        }
    }

    func stop() async {
        stopRequested.open()
        await drained.wait()
    }

    func waitUntilPrefixEmitted() async {
        await prefixEmitted.wait()
    }

    private func yield(tokens: [SpokenToken], rawText: String) {
        updateContinuation?.yield(
            TranscriptionUpdate(
                tokens: tokens,
                engineKind: engineKind,
                rawText: rawText,
                alternativeSurfaceLists: []
            )
        )
    }
}

/// Models the 19-17-46Z wipe: a long volatile tail, then a short final fragment.
final class HypothesisWipeEngine: TranscriptionEngine, @unchecked Sendable {
    var engineKind: LiveTranscriptionEngine.EngineKind = .speechTranscriber
    let committed: [String]
    let volatileTail: [String]
    let shortFinal: String

    private var updateContinuation: AsyncStream<TranscriptionUpdate>.Continuation?
    private let ready = Latch()

    init(committed: [String], volatileTail: [String], shortFinal: String) {
        self.committed = committed
        self.volatileTail = volatileTail
        self.shortFinal = shortFinal
    }

    var updates: AsyncStream<TranscriptionUpdate> {
        let pair = AsyncStream<TranscriptionUpdate>.makeStream(bufferingPolicy: .unbounded)
        updateContinuation = pair.continuation
        return pair.stream
    }

    func setContextualPhrases(_ phrases: [String]) { _ = phrases }
    func prepareIfNeeded(locale: Locale) async throws { _ = locale }
    func append(_ chunk: AudioChunk) { _ = chunk }

    func start(
        locale: Locale,
        preference: LiveTranscriptionEngine.EnginePreference
    ) async throws {
        _ = locale
        _ = preference
        Task { [weak self] in
            guard let self else { return }
            var cumulative: [String] = []
            for word in self.committed {
                cumulative.append(word)
                self.yield(
                    tokens: [SpokenToken(surface: word, isFinal: true)],
                    rawText: cumulative.joined(separator: " ")
                )
            }
            self.yield(
                tokens: self.volatileTail.map { SpokenToken(surface: $0, isFinal: false) },
                rawText: self.volatileTail.joined(separator: " ")
            )
            self.yield(
                tokens: ReadingSession.tokenizeHypothesis(self.shortFinal).map {
                    SpokenToken(surface: $0, isFinal: true)
                },
                rawText: self.shortFinal
            )
            self.ready.open()
        }
    }

    func stop() async {
        updateContinuation?.finish()
        updateContinuation = nil
    }

    func waitUntilReadyToStop() async {
        await ready.wait()
    }

    private func yield(tokens: [SpokenToken], rawText: String) {
        updateContinuation?.yield(
            TranscriptionUpdate(
                tokens: tokens,
                engineKind: engineKind,
                rawText: rawText,
                alternativeSurfaceLists: []
            )
        )
    }
}

/// One-shot async latch for test engines that emit, then wait for stop/drain.
private final class Latch: @unchecked Sendable {
    private var isOpen = false
    private var waiter: CheckedContinuation<Void, Never>?

    func open() {
        isOpen = true
        waiter?.resume()
        waiter = nil
    }

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiter = $0 }
    }
}
