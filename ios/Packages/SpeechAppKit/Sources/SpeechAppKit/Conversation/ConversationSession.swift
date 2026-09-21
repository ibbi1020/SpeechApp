import Foundation
import Observation

@MainActor
@Observable
public final class ConversationSession {
    public private(set) var phase: ConversationPhase = .idle
    public private(set) var countsAsBudgetStart = false
    public private(set) var report: ConversationReport?
    public private(set) var possibleMinorFlag = false

    public var elapsed: TimeInterval {
        guard let origin = clockOrigin else { return 0 }
        let extra = (phase == .paused ? (time.now - (pausedAt ?? time.now)) : 0)
        return max(0, time.now - origin - pausedAccumulated - extra)
    }

    private let time: any ConversationTimeSource
    private let mouth: any ConversationMouth
    private let cap: TimeInterval
    private let prefix: String
    private let stance: String
    private let openQuestion: String

    private var clockOrigin: TimeInterval?
    private var pausedAccumulated: TimeInterval = 0
    private var pausedAt: TimeInterval?
    private var lastUserSpeechAt: TimeInterval?
    private var userHasSpoken = false
    private var pendingCue: ConversationCue?
    private var wrapWarnArmed = false
    private var wrapCloseArmed = false
    private var lastUserText = ""
    private var userSpeechThisTurn: TimeInterval = 0
    private var userSpeechSeconds: TimeInterval = 0
    private var userTurns = 0
    private var speechStartedAt: TimeInterval?
    private var ghostTurn = false
    private var openSent = false
    private var openAudioRetries = 0
    private var awaitingFirstAudio = false
    private var firstAudioDeadline: TimeInterval?
    private var wrappingWaitingUpdated = false
    private var lastSentCue: ConversationCue?
    private var openIgnoreRetries = 0
    private var waitingForUser = true
    private var closed = false
    private var speechRanges: [ConversationSpeechInterval] = []
    private var userTranscript = ""

    public init(
        time: any ConversationTimeSource,
        mouth: any ConversationMouth,
        cap: TimeInterval = 15 * 60,
        prefix: String,
        stance: String,
        openQuestion: String
    ) {
        self.time = time
        self.mouth = mouth
        self.cap = cap
        self.prefix = prefix
        self.stance = stance
        self.openQuestion = openQuestion
    }

    public func beginCountdown() { phase = .countdown }

    public func countdownReachedZero(ephemeralKey: String) async throws {
        phase = .connecting
        try await mouth.connect(ephemeralKey: ephemeralKey)
    }

    public func pause() {
        guard phase == .talking else { return }
        phase = .paused
        pausedAt = time.now
    }

    public func resume() {
        guard phase == .paused, let pausedAt else { return }
        pausedAccumulated += time.now - pausedAt
        self.pausedAt = nil
        lastUserSpeechAt = time.now
        phase = .talking
    }

    public func requestStop() {}

    public func confirmStop() async { await finish(reason: .userStop) }

    public func noteConfigDrift() async { await finish(reason: .configDrift) }

    public func ingestUserText(_ text: String) { lastUserText = text }

    public func noteUserSpeech(seconds: TimeInterval) {
        userSpeechThisTurn += seconds
        userSpeechSeconds += seconds
        if seconds >= 0.3 {
            userHasSpoken = true
            lastUserSpeechAt = time.now
        }
    }

    public func queueIfAllowed(_ cue: ConversationCue) {
        guard ConversationCueAssembler.v1MaySend(cue) else { return }
        pendingCue = cue
    }

    public func tick() async {
        switch phase {
        case .connecting:
            if awaitingFirstAudio, let deadline = firstAudioDeadline, time.now >= deadline {
                if openAudioRetries < 1 {
                    openAudioRetries += 1
                    firstAudioDeadline = time.now + 8
                    try? await sendCue(.open(question: openQuestion))
                } else {
                    await finish(reason: .drop)
                }
            }
        case .talking:
            if let started = speechStartedAt, time.now - started >= 8 {
                ghostTurn = true
                speechStartedAt = nil
            }
            if userHasSpoken, let last = lastUserSpeechAt, time.now - last >= 90 {
                pause()
                return
            }
            if elapsed >= cap - 120, !wrapWarnArmed {
                wrapWarnArmed = true
                pendingCue = .wrapWarn
            }
            if elapsed >= cap, !wrapCloseArmed {
                wrapCloseArmed = true
                if waitingForUser {
                    await finish(reason: .wrap)
                } else {
                    await beginWrapClose()
                }
            }
        case .paused:
            if let pausedAt, time.now - pausedAt >= 600 {
                await finish(reason: .pauseTTL)
            }
        default:
            break
        }
    }

    public func handle(_ event: MouthEvent) async {
        if phase == .paused, event == .speechStopped { return }
        switch event {
        case .sessionUpdated:
            if wrappingWaitingUpdated {
                wrappingWaitingUpdated = false
                guard !closed else { return }
                try? await sendCue(.wrapClose)
                return
            }
            if phase == .connecting, !openSent {
                openSent = true
                awaitingFirstAudio = true
                firstAudioDeadline = time.now + 8
                try? await sendCue(.open(question: openQuestion))
            }
        case .audioDelta:
            if clockOrigin == nil {
                clockOrigin = time.now
                countsAsBudgetStart = true
                awaitingFirstAudio = false
                if phase == .connecting { phase = .talking }
            }
        case .speechStarted:
            guard phase == .talking else { return }
            ghostTurn = false
            speechStartedAt = time.now
            waitingForUser = false
            lastUserText = ""
            userSpeechThisTurn = 0
        case .speechStopped:
            await onSpeechStopped()
        case .responseDone(let transcript):
            await onResponseDone(transcript)
        case .disconnected:
            break
        case .failed:
            await finish(reason: .drop)
        case .configDrift:
            await noteConfigDrift()
        }
    }

    private func onSpeechStopped() async {
        guard phase == .talking else { return }
        let started = speechStartedAt
        let stoppedAt = time.now
        speechStartedAt = nil
        waitingForUser = true
        if ghostTurn {
            ghostTurn = false
            return
        }
        lastUserSpeechAt = time.now
        switch CrisisGate.evaluate(lastUserText) {
        case .crisis:
            await finish(reason: .crisisReferral)
            return
        case .therapyOverride:
            await finish(reason: .userStop)
            return
        case .possibleMinor:
            possibleMinorFlag = true
            await finish(reason: .userStop)
            return
        case .allow:
            break
        }
        let empty = lastUserText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if empty && userSpeechThisTurn < 0.3 { return }
        userHasSpoken = true
        userTurns += 1
        if let started, stoppedAt > started {
            speechRanges.append(ConversationSpeechInterval(start: started, end: stoppedAt))
        }
        if !empty {
            let piece = lastUserText.trimmingCharacters(in: .whitespacesAndNewlines)
            if userTranscript.isEmpty {
                userTranscript = piece
            } else {
                userTranscript += " " + piece
            }
        }
        if let pending = pendingCue, ConversationCueAssembler.v1MaySend(pending) {
            pendingCue = nil
            try? await sendCue(pending)
        } else {
            try? await sendContinue()
        }
    }

    private func onResponseDone(_ transcript: String) async {
        if case .wrapClose = lastSentCue {
            await finish(reason: .wrap)
            return
        }
        guard let cue = lastSentCue else { return }
        if ConversationCueAssembler.heard(cue, in: transcript) { return }
        switch cue {
        case .open:
            if openIgnoreRetries < 1 {
                openIgnoreRetries += 1
                try? await sendCue(.open(question: openQuestion))
            }
        case .wrapWarn:
            pendingCue = .wrapWarn
        case .wrapClose:
            await finish(reason: .wrap)
        case .codeSwitch, .fillerOk:
            break
        }
    }

    private func beginWrapClose() async {
        phase = .wrapping
        try? await mouth.updateTurnDetectionNull()
        wrappingWaitingUpdated = true
    }

    private func sendCue(_ cue: ConversationCue) async throws {
        guard !closed else { return }
        guard ConversationCueAssembler.v1MaySend(cue) else { return }
        lastSentCue = cue
        try await mouth.sendResponseCreate(
            instructions: ConversationCueAssembler.instructions(
                prefix: prefix, stance: stance, cue: cue
            )
        )
    }

    private func sendContinue() async throws {
        lastSentCue = nil
        try await mouth.sendResponseCreate(instructions: """
        \(prefix)
        \(stance)
        Answer them as you were going to. Stay on the topic. \(ConversationCueAssembler.doNotAnnounceTimer)
        """)
    }

    private func finish(reason: ConversationEndReason) async {
        guard !closed else { return }
        closed = true
        wrappingWaitingUpdated = false
        switch reason {
        case .crisisReferral: phase = .crisis
        case .drop: phase = .dropped
        default: phase = .report
        }
        // Detectors run after hang-up from recorded timestamps. Never delay
        // response.create / sendCue; live SpeechAnalyzer PCM fork is deferred.
        let unionSeconds = ConversationSpeechMetrics.unionDuration(speechRanges)
        let claimed = userSpeechSeconds > 0 ? userSpeechSeconds : unionSeconds
        let metrics = ConversationSpeechMetrics.from(
            ranges: speechRanges,
            claimedSpeechSeconds: claimed
        )
        let spokenForReport = userSpeechSeconds > 0 ? userSpeechSeconds : unionSeconds
        report = ConversationReportBuilder.build(
            userSpeechSeconds: spokenForReport,
            userTurns: userTurns,
            endReason: reason,
            extraFullLines: extraFullLines(metrics: metrics, spokenSeconds: unionSeconds > 0 ? unionSeconds : spokenForReport),
            limitedAnalysis: metrics.limitedAnalysis
        )
        await mouth.close()
    }

    private func extraFullLines(
        metrics: ConversationSpeechMetrics,
        spokenSeconds: TimeInterval
    ) -> [ConversationReport.Line] {
        guard !metrics.limitedAnalysis else { return [] }
        var lines: [ConversationReport.Line] = []
        if let pace = ConversationPace.syllablesPerMinute(
            transcript: userTranscript,
            speechSeconds: spokenSeconds
        ) {
            lines.append(ConversationReport.Line(
                label: "Pace",
                value: "\(Int(pace.rounded())) syl/min"
            ))
        }
        if speechRanges.count >= 2 {
            let pause = ConversationPauseTime.seconds(from: speechRanges)
            lines.append(ConversationReport.Line(
                label: "Pause time",
                value: String(format: "%.1fs", pause)
            ))
        }
        return lines
    }
}
