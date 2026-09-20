import Foundation
import Observation

@MainActor
@Observable
public final class ReadingSession {
    public enum Phase: Equatable, Sendable {
        case idle
        case running
        case stalled
        /// Mic still up; ASR/PCM are gated until resume.
        case paused
        /// Mic off; draining ASR finalize before the report.
        case finishing
        case finished
    }

    /// Live registration health — occupancy progress, not mic volume.
    public enum RegistrationHealth: Equatable, Sendable {
        case idle
        case keepingUp
        case fallingBehind
    }

    public private(set) var phase: Phase = .idle
    public private(set) var registrationHealth: RegistrationHealth = .idle
    public private(set) var currentWordID: String?
    /// Script words matched by the latest volatile hypothesis (not yet finalized).
    public private(set) var provisionalMatchedIDs: [String] = []
    /// Committed matches — persistent “optimistic success” trail behind the caret.
    public private(set) var committedMatchedIDs: [String] = []
    /// Sticky heard trail (provisional ∪ committed). Never rewinds mid-session — optimistic success.
    public private(set) var heardWordIDs: [String] = []
    public private(set) var marks: [LiveMark] = []
    /// Skip marks collected for the report (not painted live).
    public private(set) var liveSkipMarks: [LiveMark] = []
    public private(set) var events: [AlignmentEvent] = []
    public private(set) var showStallNudge: Bool = false
    public private(set) var engineKind: LiveTranscriptionEngine.EngineKind = .unknown
    /// Debug / stop-flush only — never shown as live transcript.
    public private(set) var volatileHint: String = ""
    public private(set) var report: SessionReport?
    /// Spoken→caret latency samples (seconds), volatile path.
    public private(set) var volatileCaretLatencies: [TimeInterval] = []
    /// Spoken→caret latency samples (seconds), final path.
    public private(set) var finalCaretLatencies: [TimeInterval] = []
    /// Mic energy above VAD threshold — drives speaking-pulse UI before ASR returns.
    public private(set) var isHearingSpeech: Bool = false
    /// Normalized mic energy 0…1 for continuous speaking feedback.
    public private(set) var speechEnergy: Float = 0
    /// Idle span-presence fields (Pass 7 UI uses aurora only; kept for kit API stability).
    public private(set) var currentSpanIndex: Int = 0
    public private(set) var spanProgress: Double = 0
    public private(set) var passedSpanIndices: [Int] = []
    public private(set) var showKeepGoingHint: Bool = false
    public private(set) var hintNextSpanIndex: Int?
    public private(set) var stuckSpanIndex: Int?
    /// JSONL diagnostics log for this session (share after Stop).
    public private(set) var diagnosticsLogURL: URL?

    public let passage: Passage
    public let ledgerAverageRate: Double?

    private let aligner: TokenAligner
    private let stallDetector: StallDetector
    private let gopScorer: any GOPScorer
    private let pcmStore = PCMStore()
    private var diagnostics: SessionDiagnostics?
    private var audioSource: (any AudioSource)?
    private var engine: (any TranscriptionEngine)?
    private var audioTask: Task<Void, Never>?
    private var transcriptTask: Task<Void, Never>?
    private var runningAccumulated: TimeInterval = 0
    private var runningStartedAt: Date?
    private var matchedSyllables: Int = 0
    private var stallEventCount: Int = 0
    private var sessionHostStart: TimeInterval?
    private var lastLoggedCaretWordID: String?
    private var enginePreference: LiveTranscriptionEngine.EnginePreference = .autoPreferSpeechTranscriber
    private var lastOccupancyAdvanceAt: TimeInterval?
    private var lastRawHypothesis: String = ""
    private static let fallingBehindSeconds: TimeInterval = 1.25
    private static let audioDrainTimeoutMs: UInt64 = 1_000
    private static let transcriptDrainTimeoutMs: UInt64 = 15_000

    public init(
        passage: Passage,
        ledgerAverageRate: Double? = nil,
        gopScorer: any GOPScorer = SpecializedSoundScorer(),
        stallTimeout: TimeInterval = 4.5
    ) {
        self.passage = passage
        self.ledgerAverageRate = ledgerAverageRate
        self.gopScorer = gopScorer
        // Minimal-pair contrast passages: exact occupancy only (ship≠sheep).
        let soft = !passage.contrastTags.contains("ɪ-i")
        self.aligner = TokenAligner(
            passage: passage,
            configuration: .init(softScriptMatch: soft)
        )
        self.stallDetector = StallDetector(
            configuration: .init(silenceTimeout: stallTimeout)
        )
        let firstID = passage.words.first?.id
        self.currentWordID = firstID
        self.currentSpanIndex = 0
    }

    public func start(
        audioSource: any AudioSource,
        engine: any TranscriptionEngine,
        preference: LiveTranscriptionEngine.EnginePreference = .autoPreferSpeechTranscriber
    ) async throws {
        self.audioSource = audioSource
        self.engine = engine
        self.enginePreference = preference
        phase = .running
        runningAccumulated = 0
        runningStartedAt = Date()
        showStallNudge = false
        provisionalMatchedIDs = []
        committedMatchedIDs = []
        heardWordIDs = []
        stallEventCount = 0
        pcmStore.secureClear()
        liveSkipMarks = []
        volatileCaretLatencies = []
        finalCaretLatencies = []
        lastLoggedCaretWordID = nil
        sessionHostStart = ProcessInfo.processInfo.systemUptime
        isHearingSpeech = false
        speechEnergy = 0
        clearSpanPresenceState()
        registrationHealth = .idle
        lastOccupancyAdvanceAt = nil
        lastRawHypothesis = ""
        let firstID = passage.words.first?.id
        currentWordID = firstID
        let diag = SessionDiagnostics(passageID: passage.id)
        diagnostics = diag
        diagnosticsLogURL = diag.logFileURL

        engine.setContextualPhrases(Self.contextualPhrases(for: passage, fromIndex: 0))
        try await engine.prepareIfNeeded(locale: Locale(identifier: "en-US"))

        // Subscribe BEFORE start — otherwise Dictation/SF yields hit a nil
        // updateContinuation and every transcript is dropped (all-skip report).
        let updates = engine.updates
        transcriptTask = Task { @MainActor [weak self] in
            for await update in updates {
                self?.handle(update: update)
            }
        }

        try await engine.start(locale: Locale(identifier: "en-US"), preference: preference)
        engineKind = engine.engineKind

        try await audioSource.start()
        audioTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for await chunk in audioSource.chunks {
                self.handle(chunk: chunk)
            }
        }
    }

    public func dismissStallNudge() {
        showStallNudge = false
        stallDetector.dismiss()
        if phase == .stalled {
            phase = .running
        }
    }

    public func pause() {
        guard phase == .running || phase == .stalled else { return }
        accumulateRunningTime()
        phase = .paused
        isHearingSpeech = false
        speechEnergy = 0
        registrationHealth = .idle
        showStallNudge = false
        stallDetector.dismiss()
    }

    public func resume() {
        guard phase == .paused else { return }
        runningStartedAt = Date()
        phase = .running
        stallDetector.dismiss()
    }

    public func stop() async -> SessionReport {
        accumulateRunningTime()
        let duration = runningAccumulated
        // Stop = mic off. Recognition still finalizes and drains before the report.
        phase = .finishing
        registrationHealth = .idle
        isHearingSpeech = false
        speechEnergy = 0
        showStallNudge = false

        await audioSource?.stop()

        // Drain remaining PCM into the analyzer before finalize. Cancelling first
        // dropped the last words the user had already spoken.
        if let audioTask {
            await Self.awaitTask(audioTask, timeoutMs: Self.audioDrainTimeoutMs)
        }
        audioTask = nil

        // Engine drains late finals into transcriptTask before closing updates.
        // Apple final p50 on device is ~6s; a 2.5s cap cut the tail.
        await engine?.stop()

        if let transcriptTask {
            await Self.awaitTask(transcriptTask, timeoutMs: Self.transcriptDrainTimeoutMs)
            transcriptTask.cancel()
        }
        transcriptTask = nil

        // Flush volatile occupancy → sticky-heard trail → unread skips.
        flushStopRecoveryMatches()

        provisionalMatchedIDs = []
        volatileHint = ""

        let trailing = aligner.finish()
        events.append(contentsOf: trailing)
        marks = aligner.liveMarks()
        liveSkipMarks = marks.filter { $0.kind == .skip }

        if !volatileCaretLatencies.isEmpty || !finalCaretLatencies.isEmpty {
            let vP99 = Self.percentile(volatileCaretLatencies, 0.99)
            let fP99 = Self.percentile(finalCaretLatencies, 0.99)
            print(
                "[ReadingSession] caret latency p99 volatile=\(String(format: "%.3f", vP99 ?? -1))s final=\(String(format: "%.3f", fP99 ?? -1))s samples_v=\(volatileCaretLatencies.count) samples_f=\(finalCaretLatencies.count)"
            )
        }

        let logURL = diagnostics?.finishSummary(
            volatileLatencies: volatileCaretLatencies,
            finalLatencies: finalCaretLatencies
        )
        diagnosticsLogURL = logURL

        let built = await SessionAnalyzer.buildReport(
            passage: passage,
            events: events,
            marks: marks,
            matchedSyllables: matchedSyllables,
            duration: duration,
            stallEventCount: stallEventCount,
            pcm: pcmStore,
            gopScorer: gopScorer,
            ledgerAverageRate: ledgerAverageRate,
            engineKind: engineKind.rawValue,
            diagnosticsLogPath: logURL?.path
        )

        pcmStore.secureClear()
        report = built
        phase = .finished
        currentWordID = nil
        clearSpanPresenceState(includeHints: false)
        showStallNudge = false
        diagnostics = nil
        return built
    }

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

    /// Candidate hypotheses for occupancy rerank. Always includes the primary
    /// `rawText` so a short n-best cannot hide the full transcript.
    nonisolated public static func occupancySurfaces(
        rawText: String,
        alternatives: [[String]],
        tokenSurfaces: [String] = []
    ) -> [[String]] {
        var candidates = alternatives
        let raw = tokenizeHypothesis(rawText)
        if !raw.isEmpty {
            candidates.append(raw)
        }
        if !tokenSurfaces.isEmpty {
            candidates.append(tokenSurfaces)
        }
        return candidates
    }

    nonisolated public static func tokenizeHypothesis(_ text: String) -> [String] {
        text.split { $0.isWhitespace || $0.isNewline }.map(String.init)
    }

    /// Sliding upcoming unigrams (+ a few rare content words), capped at 100.
    /// Prefer 1–2 token phrases per Apple AnalysisContext guidance — no trigram dump.
    nonisolated public static func contextualPhrases(
        for passage: Passage,
        fromIndex: Int = 0,
        limit: Int = 40
    ) -> [String] {
        let surfaces = passage.words.map(\.surface)
        guard !surfaces.isEmpty else { return [] }
        let start = max(0, min(fromIndex, surfaces.count - 1))
        let end = min(surfaces.count, start + max(1, limit))
        var phrases: [String] = []
        var seen = Set<String>()

        func appendUnique(_ phrase: String) {
            let key = phrase.lowercased()
            if seen.insert(key).inserted {
                phrases.append(phrase)
            }
        }

        for i in start..<end {
            appendUnique(surfaces[i])
        }
        // A few bigrams of upcoming content (skip tiny function words as lone context)
        let stop = Set(["the", "a", "an", "to", "of", "and", "in", "on", "is", "it"])
        for i in start..<min(end - 1, surfaces.count - 1) {
            let a = surfaces[i]
            let b = surfaces[i + 1]
            if !stop.contains(a.lowercased()) || !stop.contains(b.lowercased()) {
                appendUnique("\(a) \(b)")
            }
            if phrases.count >= 100 { break }
        }
        return Array(phrases.prefix(100))
    }

    nonisolated public static func percentile(_ values: [TimeInterval], _ p: Double) -> TimeInterval? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let idx = min(sorted.count - 1, max(0, Int((Double(sorted.count) - 1) * p)))
        return sorted[idx]
    }

    private func accumulateRunningTime() {
        if let start = runningStartedAt {
            runningAccumulated += Date().timeIntervalSince(start)
            runningStartedAt = nil
        }
    }

    private func handle(update: TranscriptionUpdate) {
        guard phase != .paused else { return }
        engineKind = update.engineKind
        let finals = update.tokens.filter(\.isFinal)
        let volatileTokens = update.tokens.filter { !$0.isFinal }
        let hasVolatile = !volatileTokens.isEmpty || (finals.isEmpty && !update.rawText.isEmpty)
        let previousCaret = currentWordID
        let previousHeardCount = heardWordIDs.count
        let speakingAtUpdate = isHearingSpeech

        if !update.rawText.isEmpty {
            rememberHypothesis(update.rawText)
        }

        if !finals.isEmpty {
            for token in finals {
                let produced = aligner.ingest(token)
                events.append(contentsOf: produced)
                for event in produced where event.op == .match {
                    addMatchedSyllables(from: [event])
                    recordCaretLatency(token: token, wordID: event.scriptWordID, volatile: false)
                }
                for event in produced where event.op == .skipScript {
                    if let id = event.scriptWordID {
                        diagnostics?.noteSkip(wordIDs: [id])
                    }
                }
            }
            refreshCommittedMatches()
            stickyHear(committedMatchedIDs)
            refreshLiveSkipMarks()
            refreshContextWindow()
        }

        if hasVolatile {
            let candidates = Self.occupancySurfaces(
                rawText: update.rawText,
                alternatives: update.alternativeSurfaceLists,
                tokenSurfaces: volatileTokens.map(\.surface).filter { !$0.isEmpty }
            )
            let surfaces: [String]
            if let best = aligner.bestScriptAlternative(candidates: candidates), !best.isEmpty {
                surfaces = best
            } else {
                surfaces = Self.tokenizeHypothesis(update.rawText)
            }
            let preview = aligner.previewVolatile(surfaces: surfaces)
            let proposed = preview.currentWordID ?? aligner.currentWordID
            currentWordID = aligner.monotonicWordID(proposing: proposed)
            provisionalMatchedIDs = preview.provisionalMatchedIDs
            stickyHear(preview.provisionalMatchedIDs)
            if !preview.provisionalSkippedIDs.isEmpty {
                mergeLiveSkips(scriptWordIDs: preview.provisionalSkippedIDs)
                diagnostics?.noteSkip(wordIDs: preview.provisionalSkippedIDs)
            }
            volatileHint = update.rawText
            if let firstVolatile = update.tokens.first(where: { !$0.isFinal }) {
                recordCaretLatency(token: firstVolatile, wordID: currentWordID, volatile: true)
            }
        } else if provisionalMatchedIDs.isEmpty {
            // Keep an existing occupancy trail when a short final arrives with no volatile.
            volatileHint = ""
            currentWordID = aligner.monotonicWordID(proposing: aligner.currentWordID)
        }

        if currentWordID != previousCaret || heardWordIDs.count > previousHeardCount {
            noteOccupancyAdvance()
        }

        diagnostics?.noteASRUpdate(
            engineKind: update.engineKind.rawValue,
            finalCount: finals.count,
            volatileCount: hasVolatile ? max(1, volatileTokens.count) : 0,
            caretBefore: previousCaret,
            caretAfter: currentWordID,
            wasSpeaking: speakingAtUpdate
        )
    }

    private func addMatchedSyllables(from events: [AlignmentEvent]) {
        for event in events where event.op == .match {
            guard let id = event.scriptWordID,
                  let word = passage.words.first(where: { $0.id == id }) else { continue }
            matchedSyllables += word.syllableCount
        }
    }

    private func refreshCommittedMatches() {
        committedMatchedIDs = events.compactMap { event in
            guard event.op == .match else { return nil }
            return event.scriptWordID
        }
    }

    /// Optimistic success: once a word is painted “heard,” keep it until Stop.
    private func stickyHear(_ ids: [String]) {
        var seen = Set(heardWordIDs)
        var grew = false
        for id in ids where seen.insert(id).inserted {
            heardWordIDs.append(id)
            grew = true
        }
        if grew {
            noteOccupancyAdvance()
        }
    }

    private func noteOccupancyAdvance() {
        lastOccupancyAdvanceAt = ProcessInfo.processInfo.systemUptime
        if isLivePhase {
            registrationHealth = .keepingUp
        }
    }

    private var isLivePhase: Bool {
        phase == .running || phase == .stalled
    }

    private func refreshRegistrationHealth(speaking: Bool) {
        guard isLivePhase else {
            registrationHealth = .idle
            return
        }
        guard speaking else {
            if registrationHealth == .fallingBehind {
                registrationHealth = .idle
            }
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        if let last = lastOccupancyAdvanceAt {
            registrationHealth = (now - last >= Self.fallingBehindSeconds) ? .fallingBehind : .keepingUp
        } else if let sessionHostStart, now - sessionHostStart >= Self.fallingBehindSeconds {
            registrationHealth = .fallingBehind
        }
    }

    private func refreshLiveSkipMarks() {
        liveSkipMarks = aligner.liveMarks().filter { $0.kind == .skip }
    }

    /// Paint provisional skip pills when volatile jumps ahead (keep-going recovery).
    private func mergeLiveSkips(scriptWordIDs: [String]) {
        var existing = Set(liveSkipMarks.compactMap(\.scriptWordID))
        for id in scriptWordIDs where existing.insert(id).inserted {
            liveSkipMarks.append(
                LiveMark(kind: .skip, scriptWordID: id, message: "Skipped")
            )
        }
    }

    private func refreshContextWindow() {
        engine?.setContextualPhrases(
            Self.contextualPhrases(for: passage, fromIndex: aligner.scriptCursor)
        )
    }

    private func recordCaretLatency(token: SpokenToken, wordID: String?, volatile: Bool) {
        guard let wordID, wordID != lastLoggedCaretWordID else { return }
        lastLoggedCaretWordID = wordID
        let now = ProcessInfo.processInfo.systemUptime
        let spokenAt: TimeInterval
        if let end = token.endTime {
            spokenAt = end
        } else if let start = token.startTime {
            spokenAt = start
        } else if let sessionHostStart {
            spokenAt = sessionHostStart
        } else {
            return
        }
        // Token audioTimeRange is usually relative to analyzer t=0; subtract session host start.
        let hasTokenTime = token.endTime != nil || token.startTime != nil
        let latency: TimeInterval
        if hasTokenTime, let sessionHostStart {
            latency = max(0, now - sessionHostStart - spokenAt)
        } else {
            latency = max(0, now - spokenAt)
        }
        // Clamp absurd cold-start samples
        guard latency < 10 else { return }
        if volatile {
            volatileCaretLatencies.append(latency)
        } else {
            finalCaretLatencies.append(latency)
        }
        let surface = passage.words.first(where: { $0.id == wordID })?.surface ?? ""
        diagnostics?.noteCaret(
            wordID: wordID,
            surface: surface,
            trigger: volatile ? "volatile" : "final",
            latency: latency
        )
    }

    private func handle(chunk: AudioChunk) {
        guard phase != .paused else { return }
        let handleStart = ProcessInfo.processInfo.systemUptime
        pcmStore.append(chunk)
        engine?.append(chunk)

        let rms = StallDetector.rms(chunk.samples)
        let speaking = rms >= 0.01
        isHearingSpeech = speaking
        // Soft ceiling so typical conversational levels sit near 0.6–1.0
        speechEnergy = min(1, rms / 0.06)
        refreshRegistrationHealth(speaking: speaking)

        let fired = stallDetector.process(samples: chunk.samples, at: chunk.hostTime)
        if phase != .finishing, fired {
            stallEventCount += 1
            showStallNudge = true
            phase = .stalled
        } else if phase == .stalled, !stallDetector.isStalled {
            showStallNudge = false
            phase = .running
        }

        let handleDuration = ProcessInfo.processInfo.systemUptime - handleStart
        diagnostics?.noteChunk(
            handleDuration: handleDuration,
            speaking: speaking,
            rmsEnergy: speechEnergy,
            fill: 0,
            currentWordID: currentWordID
        )
    }

    /// Optional scroll telemetry (Pass 7 UI no longer auto-scrolls).
    public func noteScroll(to wordID: String, reason: String) {
        diagnostics?.noteScroll(wordID: wordID, reason: reason)
    }

    /// Resets unused span-presence fields. Stop omits hint fields to match prior behavior.
    private func clearSpanPresenceState(includeHints: Bool = true) {
        currentSpanIndex = 0
        spanProgress = 0
        passedSpanIndices = []
        guard includeHints else { return }
        showKeepGoingHint = false
        hintNextSpanIndex = nil
        stuckSpanIndex = nil
    }

    private func pendingProvisionalMatchIDs() -> [String] {
        if !provisionalMatchedIDs.isEmpty {
            return provisionalMatchedIDs
        }
        let hypothesis = lastRawHypothesis.isEmpty ? volatileHint : lastRawHypothesis
        return previewMatchIDs(from: hypothesis)
    }

    /// Keep the hypothesis that occupies the most remaining script. Short late
    /// finals (2–3 tokens) must not replace a 10-word volatile tail.
    private func rememberHypothesis(_ text: String) {
        let incoming = (occupancy: previewMatchIDs(from: text).count, length: text.count)
        let current = (occupancy: previewMatchIDs(from: lastRawHypothesis).count, length: lastRawHypothesis.count)
        if incoming >= current {
            lastRawHypothesis = text
        }
    }

    /// On Stop: commit what the user already saw as progress before `finish()` skips the rest.
    private func flushStopRecoveryMatches() {
        absorbMatchEvents(aligner.commitProvisionalMatches(pendingProvisionalMatchIDs()))

        // Last full hypothesis if provisional list was empty/stale.
        if aligner.scriptCursor < passage.words.count {
            absorbMatchEvents(
                aligner.commitProvisionalMatches(previewMatchIDs(from: lastRawHypothesis))
            )
        }

        absorbMatchEvents(aligner.commitHeardTrail(Set(heardWordIDs)))
    }

    private func previewMatchIDs(from raw: String) -> [String] {
        guard !raw.isEmpty else { return [] }
        return aligner.previewVolatile(surfaces: Self.tokenizeHypothesis(raw)).provisionalMatchedIDs
    }

    private func absorbMatchEvents(_ produced: [AlignmentEvent]) {
        guard !produced.isEmpty else { return }
        events.append(contentsOf: produced)
        addMatchedSyllables(from: produced)
        refreshCommittedMatches()
        stickyHear(committedMatchedIDs)
    }
}
