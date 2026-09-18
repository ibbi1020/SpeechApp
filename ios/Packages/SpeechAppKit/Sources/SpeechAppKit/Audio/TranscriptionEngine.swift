import Foundation

/// Seam for live ASR so ReadingSession can run against Apple engines or file-replay harness doubles.
public protocol TranscriptionEngine: AnyObject, Sendable {
    var engineKind: LiveTranscriptionEngine.EngineKind { get }
    var updates: AsyncStream<TranscriptionUpdate> { get }
    func setContextualPhrases(_ phrases: [String])
    func prepareIfNeeded(locale: Locale) async throws
    func start(locale: Locale, preference: LiveTranscriptionEngine.EnginePreference) async throws
    func append(_ chunk: AudioChunk)
    func stop() async
}

extension LiveTranscriptionEngine: TranscriptionEngine {}

/// Emits scripted volatile→final updates for occupancy harnesses (no Speech framework).
public final class ScriptedTranscriptEngine: TranscriptionEngine, @unchecked Sendable {
    public private(set) var engineKind: LiveTranscriptionEngine.EngineKind = .unknown
    public let words: [String]
    public let wordInterval: TimeInterval
    public let emitVolatiles: Bool
    public let alternativeLists: [[[String]]]

    private var updateContinuation: AsyncStream<TranscriptionUpdate>.Continuation?
    private var emitTask: Task<Void, Never>?
    private var finishedContinuation: CheckedContinuation<Void, Never>?
    private var didFinish = false

    public init(
        words: [String],
        wordInterval: TimeInterval = 0.08,
        emitVolatiles: Bool = true,
        alternativeLists: [[[String]]] = [],
        engineKind: LiveTranscriptionEngine.EngineKind = .dictationTranscriber
    ) {
        self.words = words
        self.wordInterval = wordInterval
        self.emitVolatiles = emitVolatiles
        self.alternativeLists = alternativeLists
        self.engineKind = engineKind
    }

    public var updates: AsyncStream<TranscriptionUpdate> {
        let pair = AsyncStream<TranscriptionUpdate>.makeStream(bufferingPolicy: .bufferingNewest(64))
        updateContinuation = pair.continuation
        return pair.stream
    }

    public func setContextualPhrases(_ phrases: [String]) {
        _ = phrases
    }

    public func prepareIfNeeded(locale: Locale = Locale(identifier: "en-US")) async throws {
        _ = locale
    }

    public func start(
        locale: Locale = Locale(identifier: "en-US"),
        preference: LiveTranscriptionEngine.EnginePreference = .autoPreferSpeechTranscriber
    ) async throws {
        _ = locale
        _ = preference
        didFinish = false
        emitTask?.cancel()
        emitTask = Task { [weak self] in
            guard let self else { return }
            var cumulative: [String] = []
            for (index, word) in self.words.enumerated() {
                if Task.isCancelled { break }
                cumulative.append(word)
                let start = Double(index) * self.wordInterval
                let end = start + self.wordInterval * 0.8
                let alts = index < self.alternativeLists.count ? self.alternativeLists[index] : []

                if self.emitVolatiles {
                    self.yieldUpdate(
                        tokens: cumulative.map {
                            SpokenToken(surface: $0, startTime: start, endTime: end, isFinal: false)
                        },
                        rawText: cumulative.joined(separator: " "),
                        alternatives: alts
                    )
                    try? await Task.sleep(nanoseconds: UInt64(self.wordInterval * 0.4 * 1_000_000_000))
                }

                self.yieldUpdate(
                    tokens: [
                        SpokenToken(surface: word, startTime: start, endTime: end, isFinal: true)
                    ],
                    rawText: word,
                    alternatives: alts
                )
                try? await Task.sleep(nanoseconds: UInt64(self.wordInterval * 0.6 * 1_000_000_000))
            }
            self.markFinished()
        }
    }

    public func append(_ chunk: AudioChunk) {
        _ = chunk
    }

    public func stop() async {
        emitTask?.cancel()
        emitTask = nil
        updateContinuation?.finish()
        updateContinuation = nil
        markFinished()
    }

    /// Wait until all scripted words have been emitted (or `stop` was called).
    public func waitUntilFinished() async {
        if didFinish { return }
        await withCheckedContinuation { continuation in
            finishedContinuation = continuation
        }
    }

    private func yieldUpdate(tokens: [SpokenToken], rawText: String, alternatives: [[String]]) {
        updateContinuation?.yield(
            TranscriptionUpdate(
                tokens: tokens,
                engineKind: engineKind,
                rawText: rawText,
                alternativeSurfaceLists: alternatives
            )
        )
    }

    private func markFinished() {
        guard !didFinish else { return }
        didFinish = true
        finishedContinuation?.resume()
        finishedContinuation = nil
    }
}
