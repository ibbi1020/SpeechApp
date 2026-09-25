import Foundation
import Observation

@MainActor
@Observable
public final class MonologueSession {
    public private(set) var phase: MonologuePhase = .planning
    public private(set) var takeNumber: Int = 1
    public private(set) var takes: [MonologueTake] = []
    public private(set) var report: MonologueReport?
    public private(set) var possibleMinorFlag = false
    public var notes: String = ""
    public var reuseLine: String = ""
    /// Last clock reading from `tick()` while a take is running.
    /// `remaining` reads the time source directly, which Observation does not track,
    /// so the countdown stays on screen until something else redraws.
    public private(set) var clockSample: TimeInterval = 0
    public let store: any MonologuePromptStore

    public var prompt: String { cursor.current }
    public var ceiling: TimeInterval { MonologueCeiling.seconds(forTake: takeNumber) }

    public var elapsed: TimeInterval {
        guard let origin else { return 0 }
        let extra = (phase == .paused ? (time.now - (pausedAt ?? time.now)) : 0)
        return max(0, time.now - origin - pausedAccumulated - extra)
    }

    public var remaining: TimeInterval { max(0, ceiling - elapsed) }

    public var betweenCopy: String {
        switch takes.last?.index {
        case 1: return "Three minutes."
        case 2: return "Two minutes."
        default: return ""
        }
    }

    private var cursor: MonologuePromptCursor
    private let time: any ConversationTimeSource
    private var origin: TimeInterval?
    private var pausedAccumulated: TimeInterval = 0
    private var pausedAt: TimeInterval?
    private var liveRanges: [ConversationSpeechInterval] = []
    private var liveTranscript: String = ""

    public init(
        prompts: [String],
        store: any MonologuePromptStore,
        time: any ConversationTimeSource
    ) {
        self.cursor = MonologuePromptCursor(prompts: prompts, lastPrompt: store.lastPrompt)
        self.store = store
        self.time = time
    }

    public func skipTopic() {
        guard phase == .planning || phase == .between else { return }
        cursor.skip()
    }

    public func ready() {
        guard phase == .planning || phase == .between else { return }
        store.lastPrompt = prompt
        liveRanges = []
        liveTranscript = ""
        pausedAccumulated = 0
        pausedAt = nil
        origin = time.now
        phase = .taking
    }

    public func pause() {
        guard phase == .taking else { return }
        pausedAt = time.now
        phase = .paused
    }

    public func resume() {
        guard phase == .paused, let pausedAt else { return }
        pausedAccumulated += time.now - pausedAt
        self.pausedAt = nil
        phase = .taking
    }

    public func tick() async {
        guard phase == .taking else { return }
        clockSample = time.now
        guard remaining <= 0 else { return }
        finishTake()
    }

    public func done() { finishTake() }

    public func confirmLeave() {
        guard phase != .report, phase != .crisis else { return }
        if takes.isEmpty, phase == .planning {
            return
        }
        if phase == .taking || phase == .paused {
            snapshotTake()
        }
        emitReport(reason: takes.count == 3 ? .completed : .leftEarly)
    }

    public func ingestText(_ text: String) {
        guard phase == .taking else { return }
        switch CrisisGate.evaluate(text) {
        case .crisis:
            emitCrisis()
        case .possibleMinor:
            possibleMinorFlag = true
            rememberTranscript(text)
        case .therapyOverride, .allow:
            rememberTranscript(text)
        }
    }

    public func ingestRanges(_ ranges: [ConversationSpeechInterval]) {
        guard phase == .taking else { return }
        liveRanges = ranges
    }

    private func rememberTranscript(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        liveTranscript = trimmed
    }

    private func finishTake() {
        guard phase == .taking || phase == .paused else { return }
        snapshotTake()
        origin = nil
        pausedAt = nil
        if takeNumber == 3 {
            emitReport(reason: .completed)
            return
        }
        takeNumber += 1
        phase = .between
    }

    private func snapshotTake() {
        let wall = elapsed
        takes.append(
            MonologueTake(
                index: takeNumber,
                wallSeconds: wall,
                ranges: liveRanges,
                transcript: liveTranscript
            )
        )
        liveRanges = []
        liveTranscript = ""
    }

    private func emitReport(reason: MonologueEndReason) {
        report = MonologueReportBuilder.build(takes: takes, endReason: reason)
        phase = reason == .crisisReferral ? .crisis : .report
    }

    private func emitCrisis() {
        report = MonologueReportBuilder.build(takes: takes, endReason: .crisisReferral)
        phase = .crisis
        origin = nil
    }
}
