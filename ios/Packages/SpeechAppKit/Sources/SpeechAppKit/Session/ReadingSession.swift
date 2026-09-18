import Foundation
import Observation

@MainActor
@Observable
public final class ReadingSession {
    public enum Phase: Equatable, Sendable {
        case idle
        case running
        case stalled
        case finished
    }

    public private(set) var phase: Phase = .idle
    public private(set) var currentWordID: String?
    /// Script words matched by the latest volatile hypothesis (not yet finalized).
    public private(set) var provisionalMatchedIDs: [String] = []
    /// Committed matches — persistent “optimistic success” trail behind the caret.
    public private(set) var committedMatchedIDs: [String] = []
    /// Sticky heard trail (provisional ∪ committed). Never rewinds mid-session — optimistic success.
    public private(set) var heardWordIDs: [String] = []
    public private(set) var marks: [LiveMark] = []
    /// Skip marks visible live as blinking pills (subset of marks).
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
    /// 0…1 left-to-right fill of the presence word while speaking (mirrors `presenceProgress`).
    public private(set) var optimisticWordProgress: Double = 0
    /// Live “with you” caret — may walk ahead of ASR without committing heard occupancy.
    public private(set) var presenceWordID: String?
    /// 0…1 fill on `presenceWordID`.
    public private(set) var presenceProgress: Double = 0
    /// Words presence fully walked that ASR has not sticky-heard yet.
    public private(set) var presenceTrailIDs: [String] = []
    /// Experience nudge: ASR isn’t locking — keep reading; next word is gently suggested.
    public private(set) var showKeepGoingHint: Bool = false
    /// Soft suggestion (not the caret). Next word to try if stuck — never steals focus.
    public private(set) var hintNextWordID: String?
    /// Word we’re stuck trying to lock (still the caret).
    public private(set) var stuckWordID: String?
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
    private var startedAt: Date?
    private var matchedSyllables: Int = 0
    private var stallEventCount: Int = 0
    private var sessionHostStart: TimeInterval?
    private var lastLoggedCaretWordID: String?
    private var enginePreference: LiveTranscriptionEngine.EnginePreference = .autoPreferSpeechTranscriber
    private var presenceState = PresenceWalkState()
    private var wordIDList: [String] = []
    private var syllableByID: [String: Int] = [:]
    private var stuckSpeechStartedAt: TimeInterval?
    private var lastCaretForStuckTracking: String?
    private var lastHintLoggedFor: String?

    public init(
        passage: Passage,
        ledgerAverageRate: Double? = nil,
        gopScorer: any GOPScorer = SpecializedSoundScorer(),
        stallTimeout: TimeInterval = 4.5
    ) {
        self.passage = passage
        self.ledgerAverageRate = ledgerAverageRate
        self.gopScorer = gopScorer
        self.aligner = TokenAligner(
            passage: passage,
            configuration: .init(softScriptMatch: true)
        )
        self.stallDetector = StallDetector(
            configuration: .init(silenceTimeout: stallTimeout)
        )
        self.wordIDList = passage.words.map(\.id)
        self.syllableByID = Dictionary(uniqueKeysWithValues: passage.words.map { ($0.id, $0.syllableCount) })
        let firstID = passage.words.first?.id
        self.currentWordID = firstID
        self.presenceWordID = firstID
        self.presenceState = PresenceWalkState(presenceWordID: firstID)
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
        startedAt = Date()
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
        optimisticWordProgress = 0
        presenceProgress = 0
        presenceTrailIDs = []
        let firstID = passage.words.first?.id
        presenceWordID = firstID
        presenceState = PresenceWalkState(presenceWordID: firstID)
        showKeepGoingHint = false
        hintNextWordID = nil
        stuckWordID = nil
        stuckSpeechStartedAt = nil
        lastCaretForStuckTracking = nil
        lastHintLoggedFor = nil
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

    public func stop() async -> SessionReport {
        audioTask?.cancel()
        await audioSource?.stop()

        // Finalize recognizer WHILE transcriptTask is still alive so late finals ingest.
        await engine?.stop()
        // Brief drain for finalize callbacks / last volatile→final flush.
        try? await Task.sleep(for: .milliseconds(200))
        transcriptTask?.cancel()
        transcriptTask = nil

        // What the user already saw as blue progress must become committed matches,
        // otherwise finish() marks the whole script as skipped.
        let provisionalIDs: [String]
        if !provisionalMatchedIDs.isEmpty {
            provisionalIDs = provisionalMatchedIDs
        } else if !volatileHint.isEmpty {
            let surfaces = volatileHint
                .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
                .map(String.init)
            provisionalIDs = aligner.previewVolatile(surfaces: surfaces).provisionalMatchedIDs
        } else {
            provisionalIDs = []
        }
        if !provisionalIDs.isEmpty {
            let committed = aligner.commitProvisionalMatches(provisionalIDs)
            events.append(contentsOf: committed)
            addMatchedSyllables(from: committed)
            refreshCommittedMatches()
            stickyHear(committedMatchedIDs)
        }

        provisionalMatchedIDs = []
        volatileHint = ""

        let trailing = aligner.finish()
        events.append(contentsOf: trailing)
        // Evaluative marks (extra / substitute) appear only after Stop.
        // Skip pills were already live; full mark set is for the report.
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

        let duration = Date().timeIntervalSince(startedAt ?? Date())
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
        presenceWordID = nil
        presenceProgress = 0
        presenceTrailIDs = []
        optimisticWordProgress = 0
        showStallNudge = false
        diagnostics = nil
        return built
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

    private func handle(update: TranscriptionUpdate) {
        engineKind = update.engineKind
        let finals = update.tokens.filter(\.isFinal)
        let volatileTokens = update.tokens.filter { !$0.isFinal }
        let hasVolatile = !volatileTokens.isEmpty || (finals.isEmpty && !update.rawText.isEmpty)
        let previousCaret = currentWordID
        let speakingAtUpdate = isHearingSpeech

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
            let surfaces: [String]
            if let best = aligner.bestScriptAlternative(candidates: update.alternativeSurfaceLists),
               !best.isEmpty {
                surfaces = best
            } else {
                surfaces = update.rawText
                    .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
                    .map(String.init)
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
        } else {
            provisionalMatchedIDs = []
            volatileHint = ""
            currentWordID = aligner.monotonicWordID(proposing: aligner.currentWordID)
        }

        diagnostics?.noteASRUpdate(
            engineKind: update.engineKind.rawValue,
            finalCount: finals.count,
            volatileCount: hasVolatile ? max(1, volatileTokens.count) : 0,
            caretBefore: previousCaret,
            caretAfter: currentWordID,
            wasSpeaking: speakingAtUpdate
        )

        if currentWordID != previousCaret {
            reconcilePresenceWithASR()
            clearKeepGoingHint()
        } else {
            prunePresenceTrailAgainstHeard()
            evaluateKeepGoingHint()
        }
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
        for id in ids where seen.insert(id).inserted {
            heardWordIDs.append(id)
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

    private func clearKeepGoingHint() {
        showKeepGoingHint = false
        hintNextWordID = nil
        stuckWordID = nil
        stuckSpeechStartedAt = nil
        lastCaretForStuckTracking = currentWordID
        lastHintLoggedFor = nil
    }

    /// After speech without ASR lock-in, suggest the next word — do not move the caret.
    /// Thresholds align with caret_freeze diagnostics (0.8s speaking / fill ≥0.85).
    /// Hint sits one ahead of the **presence** cursor so it stays useful during a walk.
    private func evaluateKeepGoingHint() {
        guard phase == .running || phase == .stalled else { return }
        let anchor = presenceWordID ?? currentWordID
        guard let caret = anchor,
              let index = passage.words.firstIndex(where: { $0.id == caret }),
              index + 1 < passage.words.count else {
            clearKeepGoingHint()
            return
        }
        // Already heard the ASR caret and presence hasn't walked past — no nudge.
        if let asr = currentWordID,
           (heardWordIDs.contains(asr) || provisionalMatchedIDs.contains(asr)),
           presenceWordID == asr || presenceWordID == nil {
            clearKeepGoingHint()
            return
        }

        if lastCaretForStuckTracking != caret {
            lastCaretForStuckTracking = caret
            stuckSpeechStartedAt = nil
        }

        let now = ProcessInfo.processInfo.systemUptime
        if isHearingSpeech {
            if stuckSpeechStartedAt == nil {
                stuckSpeechStartedAt = now
            }
        }

        let spokenLongEnough: Bool = {
            guard let started = stuckSpeechStartedAt else { return false }
            return now - started >= SessionDiagnostics.freezeSpeakingSeconds
        }()
        let filledEnough = presenceProgress >= 0.85

        if spokenLongEnough || filledEnough {
            let nextID = passage.words[index + 1].id
            stuckWordID = caret
            hintNextWordID = nextID
            showKeepGoingHint = true
            if lastHintLoggedFor != caret {
                lastHintLoggedFor = caret
                diagnostics?.noteHint(stuckWordID: caret, nextWordID: nextID)
            }
        }
    }

    private func refreshContextWindow() {
        engine?.setContextualPhrases(
            Self.contextualPhrases(for: passage, fromIndex: aligner.scriptCursor)
        )
    }

    private func publishPresence(_ state: PresenceWalkState, event: PresenceWalkEvent?) {
        presenceState = state
        presenceWordID = state.presenceWordID
        presenceProgress = state.presenceProgress
        presenceTrailIDs = state.presenceTrailIDs
        optimisticWordProgress = state.presenceProgress
        switch event {
        case .advanced(let from, let to):
            diagnostics?.notePresenceAdvance(from: from, to: to)
        case .snapped(let to):
            diagnostics?.notePresenceSnap(to: to)
        case nil:
            break
        }
    }

    private func prunePresenceTrailAgainstHeard() {
        let heard = Set(heardWordIDs)
        let pruned = presenceState.presenceTrailIDs.filter { !heard.contains($0) }
        guard pruned != presenceState.presenceTrailIDs else { return }
        presenceState.presenceTrailIDs = pruned
        presenceTrailIDs = pruned
    }

    private func reconcilePresenceWithASR() {
        let (next, event) = PresenceWalk.reconcile(
            state: presenceState,
            asrWordID: currentWordID,
            wordIDs: wordIDList,
            heardIDs: Set(heardWordIDs),
            speaking: isHearingSpeech,
            now: ProcessInfo.processInfo.systemUptime
        )
        publishPresence(next, event: event)
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
        let handleStart = ProcessInfo.processInfo.systemUptime
        pcmStore.append(chunk)
        engine?.append(chunk)

        let rms = StallDetector.rms(chunk.samples)
        let speaking = rms >= 0.01
        isHearingSpeech = speaking
        // Soft ceiling so typical conversational levels sit near 0.6–1.0
        speechEnergy = min(1, rms / 0.06)

        updatePresenceWalk(speaking: speaking)
        evaluateKeepGoingHint()

        let fired = stallDetector.process(samples: chunk.samples, at: chunk.hostTime)
        if fired {
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
            fill: presenceProgress,
            currentWordID: presenceWordID ?? currentWordID
        )
    }

    /// Called from the reading UI when a comfort-band scroll actually fires.
    public func noteScroll(to wordID: String, reason: String) {
        diagnostics?.noteScroll(wordID: wordID, reason: reason)
    }

    /// Mic-driven presence fill / walk — stays with speech when ASR stalls.
    private func updatePresenceWalk(speaking: Bool) {
        let (next, event) = PresenceWalk.tick(
            state: presenceState,
            speaking: speaking,
            now: ProcessInfo.processInfo.systemUptime,
            wordIDs: wordIDList,
            syllableCounts: syllableByID,
            asrWordID: currentWordID,
            heardIDs: Set(heardWordIDs)
        )
        publishPresence(next, event: event)
    }
}
