import AVFoundation
import Foundation
import Speech

/// Finalized (and optional volatile) spoken tokens from the live recognizer.
public struct TranscriptionUpdate: Sendable, Equatable {
    public let tokens: [SpokenToken]
    public let engineKind: LiveTranscriptionEngine.EngineKind
    public let rawText: String
    /// Alternative surface lists (n-best) for script rerank. Empty when unavailable.
    public let alternativeSurfaceLists: [[String]]

    public init(
        tokens: [SpokenToken],
        engineKind: LiveTranscriptionEngine.EngineKind,
        rawText: String,
        alternativeSurfaceLists: [[String]] = []
    ) {
        self.tokens = tokens
        self.engineKind = engineKind
        self.rawText = rawText
        self.alternativeSurfaceLists = alternativeSurfaceLists
    }
}

/// Wraps SpeechAnalyzer + DictationTranscriber, with SFSpeechRecognizer on-device fallback.
public final class LiveTranscriptionEngine: @unchecked Sendable {
    public enum EngineKind: String, Sendable, Equatable {
        case speechTranscriber
        case dictationTranscriber
        case sfSpeechRecognizerOnDevice
        /// Cloud streaming STT (`grok-voice-transcribe-2.0`) through the local relay.
        case grokVoiceTranscribe
        case unavailable
        case unknown
    }

    public enum Availability: Equatable, Sendable {
        case speechTranscriberReady
        case dictationTranscriberReady
        case dictationTranscriberNeedsDownload
        case fallbackSFSpeechRecognizer
        case unavailable(String)
    }

    /// A/B arm for live follow-along engines.
    public enum EnginePreference: Sendable, Equatable {
        /// Prefer SpeechTranscriber when assets exist, else Dictation, else SF.
        case autoPreferSpeechTranscriber
        /// Force SpeechTranscriber (+ fastResults) when available.
        case speechTranscriber
        /// Force DictationTranscriber (+ atypicalSpeech + contextualStrings).
        case dictationTranscriber
    }

    public private(set) var engineKind: EngineKind = .unknown

    private var analyzer: SpeechAnalyzer?
    private var dictationTranscriber: DictationTranscriber?
    private var speechTranscriber: SpeechTranscriber?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?
    private var updateContinuation: AsyncStream<TranscriptionUpdate>.Continuation?
    private var emittedFinalSurfaces: [String] = []
    private var contextualPhrases: [String] = []
    private var preparedFormat: AVAudioFormat?
    private var enginePreference: EnginePreference = .autoPreferSpeechTranscriber

    // Fallback path
    private var fallbackRecognizer: SFSpeechRecognizer?
    private var fallbackRequest: SFSpeechAudioBufferRecognitionRequest?
    private var fallbackTask: SFSpeechRecognitionTask?
    private var converter: AVAudioConverter?
    private var targetFormat: AVAudioFormat?

    public init() {}

    /// Phrases to bias recognition toward (known passage). Cap at 100 per Apple AnalysisContext.
    public func setContextualPhrases(_ phrases: [String]) {
        var seen = Set<String>()
        var unique: [String] = []
        for phrase in phrases {
            let trimmed = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            if seen.insert(key).inserted {
                unique.append(trimmed)
            }
            if unique.count >= 100 { break }
        }
        contextualPhrases = unique
    }

    public var updates: AsyncStream<TranscriptionUpdate> {
        let pair = AsyncStream<TranscriptionUpdate>.makeStream(bufferingPolicy: .bufferingNewest(64))
        updateContinuation = pair.continuation
        return pair.stream
    }

    /// Probe SpeechTranscriber, then DictationTranscriber, then SFSpeechRecognizer.
    public static func checkAvailability(
        locale: Locale = Locale(identifier: "en-US")
    ) async -> Availability {
        // Prefer the newer SpeechTranscriber model when assets are available.
        let speechProbe = SpeechTranscriber(
            locale: locale,
            preset: .timeIndexedProgressiveTranscription
        )
        let speechStatus = await AssetInventory.status(forModules: [speechProbe])
        switch speechStatus {
        case .installed, .supported, .downloading:
            return .speechTranscriberReady
        case .unsupported:
            break
        @unknown default:
            break
        }

        let probe = DictationTranscriber(locale: locale, preset: .progressiveShortDictation)
        let status = await AssetInventory.status(forModules: [probe])
        switch status {
        case .installed:
            return .dictationTranscriberReady
        case .supported, .downloading:
            return .dictationTranscriberNeedsDownload
        case .unsupported:
            if SFSpeechRecognizer(locale: locale)?.isAvailable == true {
                return .fallbackSFSpeechRecognizer
            }
            return .unavailable("DictationTranscriber unsupported and SFSpeechRecognizer unavailable.")
        @unknown default:
            if SFSpeechRecognizer(locale: locale)?.isAvailable == true {
                return .fallbackSFSpeechRecognizer
            }
            return .unavailable("Unknown AssetInventory status.")
        }
    }

    public static func ensureDictationAssets(
        locale: Locale = Locale(identifier: "en-US")
    ) async throws {
        let module = DictationTranscriber(locale: locale, preset: .progressiveShortDictation)
        let status = await AssetInventory.status(forModules: [module])
        if status == .installed { return }
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
            try await request.downloadAndInstall()
        }
    }

    public static func ensureSpeechTranscriberAssets(
        locale: Locale = Locale(identifier: "en-US")
    ) async throws {
        let module = SpeechTranscriber(locale: locale, preset: .timeIndexedProgressiveTranscription)
        let status = await AssetInventory.status(forModules: [module])
        if status == .installed { return }
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
            try await request.downloadAndInstall()
        }
    }

    /// Preheat analyzer modules so first volatile arrives faster.
    public func prepareIfNeeded(locale: Locale = Locale(identifier: "en-US")) async throws {
        let availability = await Self.checkAvailability(locale: locale)
        switch availability {
        case .speechTranscriberReady:
            try? await Self.ensureSpeechTranscriberAssets(locale: locale)
            let module = SpeechTranscriber(locale: locale, preset: .timeIndexedProgressiveTranscription)
            preparedFormat = await Self.resolveAudioFormat(compatibleWith: [module])
            // Discard — start() creates a fresh analyzer; this only warms system assets.
            try await Self.warmAnalyzer(modules: [module], format: preparedFormat)
        case .dictationTranscriberReady, .dictationTranscriberNeedsDownload:
            try? await Self.ensureDictationAssets(locale: locale)
            let module = DictationTranscriber(locale: locale, preset: .progressiveShortDictation)
            preparedFormat = await Self.resolveAudioFormat(compatibleWith: [module])
            try await Self.warmAnalyzer(modules: [module], format: preparedFormat)
        default:
            break
        }
    }

    public func start(
        locale: Locale = Locale(identifier: "en-US"),
        preference: EnginePreference = .autoPreferSpeechTranscriber
    ) async throws {
        emittedFinalSurfaces = []
        enginePreference = preference

        // Required for SFSpeechRecognizer path; harmless if SpeechAnalyzer-only.
        try await Self.requestSpeechAuthorization()

        let availability = await Self.checkAvailability(locale: locale)

        switch preference {
        case .speechTranscriber:
            if case .speechTranscriberReady = availability {
                try await Self.ensureSpeechTranscriberAssets(locale: locale)
                try await startSpeechTranscriber(locale: locale)
                return
            }
            // Fall through to SF if SpeechTranscriber unavailable.
        case .dictationTranscriber:
            switch availability {
            case .dictationTranscriberReady, .dictationTranscriberNeedsDownload, .speechTranscriberReady:
                // speechTranscriberReady still implies Dictation assets may install.
                try await Self.ensureDictationAssets(locale: locale)
                try await startDictationTranscriber(locale: locale)
                return
            default:
                break
            }
        case .autoPreferSpeechTranscriber:
            switch availability {
            case .speechTranscriberReady:
                try await Self.ensureSpeechTranscriberAssets(locale: locale)
                try await startSpeechTranscriber(locale: locale)
                return
            case .dictationTranscriberReady, .dictationTranscriberNeedsDownload:
                try await Self.ensureDictationAssets(locale: locale)
                try await startDictationTranscriber(locale: locale)
                return
            case .fallbackSFSpeechRecognizer, .unavailable:
                break
            }
        }

        try startFallbackRecognizer(locale: locale)
    }

    public static func requestSpeechAuthorization() async throws {
        let status = SFSpeechRecognizer.authorizationStatus()
        switch status {
        case .authorized:
            return
        case .denied, .restricted:
            throw TranscriptionEngineError.speechAuthorizationDenied
        case .notDetermined:
            let granted: Bool = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { result in
                    continuation.resume(returning: result == .authorized)
                }
            }
            if !granted {
                throw TranscriptionEngineError.speechAuthorizationDenied
            }
        @unknown default:
            throw TranscriptionEngineError.speechAuthorizationDenied
        }
    }

    public func append(_ chunk: AudioChunk) {
        guard let format = targetFormat else { return }
        guard let pcm = floatBuffer(samples: chunk.samples, sampleRate: chunk.sampleRate, target: format) else {
            return
        }

        if let continuation = inputContinuation {
            continuation.yield(AnalyzerInput(buffer: pcm))
        }
        fallbackRequest?.append(pcm)
    }

    /// Stop accepting audio, finalize recognition, and drain late finals into
    /// `updates` before closing the stream. Cancelling first dropped end-of-utterance tokens.
    public func stop() async {
        inputContinuation?.finish()
        inputContinuation = nil

        // Finalize while resultsTask still consumes results.
        if let analyzer {
            try? await analyzer.finalizeAndFinishThroughEndOfInput()
        }
        analyzer = nil
        dictationTranscriber = nil
        speechTranscriber = nil

        if let resultsTask {
            await Self.awaitTask(resultsTask, timeoutMs: Self.resultsDrainTimeoutMs)
            resultsTask.cancel()
        }
        resultsTask = nil

        await drainFallback()

        // Close only after drain so ReadingSession can ingest late finals.
        updateContinuation?.finish()
        updateContinuation = nil
    }

    private func drainFallback() async {
        fallbackRequest?.endAudio()
        if fallbackTask != nil {
            try? await Task.sleep(for: .milliseconds(800))
        }
        fallbackTask?.cancel()
        fallbackTask = nil
        fallbackRequest = nil
        fallbackRecognizer = nil
    }

    /// Apple on-device final p50 is ~6s; shorter caps cut the occupancy tail.
    private static let resultsDrainTimeoutMs: UInt64 = 15_000

    private static func awaitTask(_ task: Task<Void, Never>, timeoutMs: UInt64) async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await task.value }
            group.addTask {
                try? await Task.sleep(for: .milliseconds(timeoutMs))
            }
            _ = await group.next()
            group.cancelAll()
        }
    }

    // MARK: - SpeechTranscriber path

    private func startSpeechTranscriber(locale: Locale) async throws {
        let configured = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults, .fastResults, .alternativeTranscriptions],
            attributeOptions: [.audioTimeRange]
        )

        let analyzer = SpeechAnalyzer(modules: [configured])
        // SpeechTranscriber does not consume contextualStrings; still set for analyzer context.
        if !contextualPhrases.isEmpty {
            let context = AnalysisContext()
            context.contextualStrings[.general] = contextualPhrases
            try? await analyzer.setContext(context)
        }

        self.speechTranscriber = configured
        self.analyzer = analyzer
        self.engineKind = .speechTranscriber

        if let preparedFormat {
            targetFormat = preparedFormat
        } else {
            targetFormat = await Self.resolveAudioFormat(compatibleWith: [configured])
        }
        if let format = targetFormat {
            try? await analyzer.prepareToAnalyze(in: format)
        }

        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        inputContinuation = continuation
        try await analyzer.start(inputSequence: stream)

        resultsTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await result in configured.results {
                    self.handleSpeechTranscriberResult(result)
                }
            } catch {
                // Stream ended or cancelled.
            }
        }
    }

    private func handleSpeechTranscriberResult(_ result: SpeechTranscriber.Result) {
        emitAnalyzerResult(
            text: String(result.text.characters),
            range: result.range,
            alternatives: result.alternatives,
            isFinal: result.isFinal,
            engineKind: .speechTranscriber
        )
    }

    // MARK: - DictationTranscriber path

    private func startDictationTranscriber(locale: Locale) async throws {
        let configured = DictationTranscriber(
            locale: locale,
            contentHints: [.shortForm, .atypicalSpeech],
            transcriptionOptions: [],
            reportingOptions: [.volatileResults, .frequentFinalization, .alternativeTranscriptions],
            attributeOptions: [.audioTimeRange]
        )

        let analyzer = SpeechAnalyzer(modules: [configured])
        if !contextualPhrases.isEmpty {
            let context = AnalysisContext()
            context.contextualStrings[.general] = contextualPhrases
            try await analyzer.setContext(context)
        }

        self.dictationTranscriber = configured
        self.analyzer = analyzer
        self.engineKind = .dictationTranscriber

        if let preparedFormat {
            targetFormat = preparedFormat
        } else {
            targetFormat = await Self.resolveAudioFormat(compatibleWith: [configured])
        }
        if let format = targetFormat {
            try? await analyzer.prepareToAnalyze(in: format)
        }

        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        inputContinuation = continuation
        try await analyzer.start(inputSequence: stream)

        resultsTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await result in configured.results {
                    self.handleDictationResult(result)
                }
            } catch {
                // Stream ended or cancelled.
            }
        }
    }

    private func handleDictationResult(_ result: DictationTranscriber.Result) {
        emitAnalyzerResult(
            text: String(result.text.characters),
            range: result.range,
            alternatives: result.alternatives,
            isFinal: result.isFinal,
            engineKind: .dictationTranscriber
        )
    }

    private func emitAnalyzerResult(
        text: String,
        range: CMTimeRange?,
        alternatives: [AttributedString],
        isFinal: Bool,
        engineKind: EngineKind
    ) {
        let parts = Self.wordSurfaces(from: text)
        guard !parts.isEmpty else { return }
        let times = Self.perWordTimes(wordCount: parts.count, fallbackRange: range)
        let alternativeLists = Self.alternativeLists(from: alternatives)

        let tokens: [SpokenToken]
        if isFinal {
            let fresh = Self.deltaFinals(parts: parts, alreadyEmitted: emittedFinalSurfaces)
            emittedFinalSurfaces.append(contentsOf: fresh)
            guard !fresh.isEmpty else { return }
            let offset = parts.count - fresh.count
            tokens = Self.tokens(from: fresh, times: times, offset: offset, isFinal: true)
        } else {
            tokens = Self.tokens(from: parts, times: times, offset: 0, isFinal: false)
        }

        updateContinuation?.yield(
            TranscriptionUpdate(
                tokens: tokens,
                engineKind: engineKind,
                rawText: text,
                alternativeSurfaceLists: alternativeLists
            )
        )
    }

    /// If `parts` extends a prior cumulative hypothesis, emit only the new suffix;
    /// otherwise treat `parts` as a fresh finalized segment.
    static func deltaFinals(parts: [String], alreadyEmitted: [String]) -> [String] {
        guard !alreadyEmitted.isEmpty else { return parts }
        let emittedNorm = alreadyEmitted.map(ScriptWord.normalize)
        let partsNorm = parts.map(ScriptWord.normalize)
        if partsNorm.count >= emittedNorm.count,
           Array(partsNorm.prefix(emittedNorm.count)) == emittedNorm {
            return Array(parts.suffix(from: alreadyEmitted.count))
        }
        return parts
    }

    // MARK: - SFSpeechRecognizer fallback

    private func startFallbackRecognizer(locale: Locale) throws {
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            engineKind = .unavailable
            throw TranscriptionEngineError.unavailable
        }
        // Probe support — do not assign true. Cloud fallback is opt-in elsewhere.
        guard recognizer.supportsOnDeviceRecognition else {
            engineKind = .unavailable
            throw TranscriptionEngineError.onDeviceUnsupported
        }
        fallbackRecognizer = recognizer
        engineKind = .sfSpeechRecognizerOnDevice

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        if !contextualPhrases.isEmpty {
            request.contextualStrings = contextualPhrases
        }
        request.taskHint = .dictation
        fallbackRequest = request

        targetFormat = Self.defaultPCMFormat

        var previouslyEmitted = 0
        fallbackTask = recognizer.recognitionTask(with: request) { [weak self] result, _ in
            guard let self, let result else { return }
            let text = result.bestTranscription.formattedString
            let parts = text.split(whereSeparator: \.isWhitespace).map(String.init).filter { !$0.isEmpty }
            if result.isFinal {
                if parts.count > previouslyEmitted {
                    let fresh = parts[previouslyEmitted...].map {
                        SpokenToken(surface: String($0), isFinal: true)
                    }
                    previouslyEmitted = parts.count
                    self.updateContinuation?.yield(
                        TranscriptionUpdate(
                            tokens: Array(fresh),
                            engineKind: .sfSpeechRecognizerOnDevice,
                            rawText: text
                        )
                    )
                }
            } else if !parts.isEmpty {
                // Commit stable prefix; keep the last word volatile for live cursor.
                let stableCount = max(0, parts.count - 1)
                var tokens: [SpokenToken] = []
                if stableCount > previouslyEmitted {
                    tokens.append(contentsOf: parts[previouslyEmitted..<stableCount].map {
                        SpokenToken(surface: String($0), isFinal: true)
                    })
                    previouslyEmitted = stableCount
                }
                tokens.append(SpokenToken(surface: parts[parts.count - 1], isFinal: false))
                self.updateContinuation?.yield(
                    TranscriptionUpdate(
                        tokens: tokens,
                        engineKind: .sfSpeechRecognizerOnDevice,
                        rawText: text
                    )
                )
            }
        }
    }

    // MARK: - Helpers

    private static let defaultPCMFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16_000,
        channels: 1,
        interleaved: false
    )

    private static func resolveAudioFormat(compatibleWith modules: [any SpeechModule]) async -> AVAudioFormat? {
        await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: modules) ?? defaultPCMFormat
    }

    private static func warmAnalyzer(modules: [any SpeechModule], format: AVAudioFormat?) async throws {
        guard let format else { return }
        let analyzer = SpeechAnalyzer(modules: modules)
        try await analyzer.prepareToAnalyze(in: format)
        _ = analyzer
    }

    private static func tokens(
        from surfaces: [String],
        times: [(TimeInterval?, TimeInterval?)],
        offset: Int,
        isFinal: Bool
    ) -> [SpokenToken] {
        surfaces.enumerated().map { index, surface in
            let timeIndex = offset + index
            let time = timeIndex < times.count ? times[timeIndex] : (nil, nil)
            return SpokenToken(
                surface: surface,
                startTime: time.0,
                endTime: time.1,
                isFinal: isFinal
            )
        }
    }

    public static func tokenize(
        text: String,
        isFinal: Bool,
        range: CMTimeRange? = nil
    ) -> [SpokenToken] {
        let parts = wordSurfaces(from: text)
        guard !parts.isEmpty else { return [] }
        let times = perWordTimes(wordCount: parts.count, fallbackRange: range)
        return tokens(from: parts, times: times, offset: 0, isFinal: isFinal)
    }

    static func wordSurfaces(from text: String) -> [String] {
        text
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    /// Distribute result audio range evenly across words when per-run ranges are absent.
    static func perWordTimes(
        wordCount: Int,
        fallbackRange: CMTimeRange?
    ) -> [(TimeInterval?, TimeInterval?)] {
        guard wordCount > 0 else { return [] }
        guard let fallbackRange else {
            return Array(repeating: (nil, nil), count: wordCount)
        }
        let start = CMTimeGetSeconds(fallbackRange.start)
        let duration = CMTimeGetSeconds(fallbackRange.duration)
        let step = duration / Double(wordCount)
        return (0..<wordCount).map { i in
            (start + step * Double(i), start + step * Double(i + 1))
        }
    }

    static func alternativeLists(from alternatives: [AttributedString]) -> [[String]] {
        alternatives.map { wordSurfaces(from: String($0.characters)) }.filter { !$0.isEmpty }
    }

    private func floatBuffer(
        samples: [Float],
        sampleRate: Double,
        target: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        let sourceFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        )!
        guard let source = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: AVAudioFrameCount(samples.count)) else {
            return nil
        }
        source.frameLength = AVAudioFrameCount(samples.count)
        if let channel = source.floatChannelData?[0] {
            for i in samples.indices {
                channel[i] = samples[i]
            }
        }

        if abs(sampleRate - target.sampleRate) < 1, sourceFormat.commonFormat == target.commonFormat {
            return source
        }

        let ratio = target.sampleRate / sampleRate
        let capacity = AVAudioFrameCount(Double(samples.count) * ratio) + 32
        guard let converted = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else {
            return nil
        }
        let localConverter = AVAudioConverter(from: sourceFormat, to: target)
        converter = localConverter
        guard let localConverter else { return source }

        var error: NSError?
        var consumed = false
        localConverter.convert(to: converted, error: &error) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return source
        }
        if error != nil { return source }
        return converted
    }
}

public enum TranscriptionEngineError: Error, Sendable {
    case unavailable
    case onDeviceUnsupported
    case speechAuthorizationDenied
}
