import Foundation

/// Island look. Pause is its own state so the chip does not keep the listening motion.
public enum ConversationIslandOrb: String, Equatable, Sendable {
    case listening
    case speaking
    case paused
}

/// Phases that stay on the island. Terminal phases end it.
public enum ConversationIslandPhase: String, Equatable, Sendable {
    case talking
    case paused
    case wrapping
}

/// Where the system draws the activity. Compact and expanded are the two Phone states.
public enum ConversationLiveActivitySurface: Equatable, Sendable {
    case compact
    case minimal
    case expanded
    case lockScreen
}

/// What the app should do with the one Conversation activity.
public enum ConversationLiveActivityCommand: Equatable, Sendable {
    case none
    case start(ConversationLiveActivitySnapshot)
    case update(ConversationLiveActivitySnapshot)
    case end
}

/// Values the island can render without a mic tap or a WebView.
public struct ConversationLiveActivitySnapshot: Equatable, Sendable {
    public var phase: ConversationIslandPhase
    public var orb: ConversationIslandOrb
    /// Lower bound of the count-up timer. Shifts forward by completed pauses.
    public var timerStart: Date
    public var timerEnd: Date
    /// Set while paused so the system timer freezes. Nil while running.
    public var pauseTime: Date?
    public var phrase: String
    public var phraseIsPartner: Bool

    public init(
        phase: ConversationIslandPhase,
        orb: ConversationIslandOrb,
        timerStart: Date,
        timerEnd: Date,
        pauseTime: Date?,
        phrase: String,
        phraseIsPartner: Bool
    ) {
        self.phase = phase
        self.orb = orb
        self.timerStart = timerStart
        self.timerEnd = timerEnd
        self.pauseTime = pauseTime
        self.phrase = phrase
        self.phraseIsPartner = phraseIsPartner
    }
}

/// Inputs the session view already has. No ActivityKit types.
public struct ConversationLiveActivityInput: Equatable, Sendable {
    public var exercise: PracticeFormat.Kind
    public var phase: ConversationPhase
    public var floor: ConversationFloorOwner
    public var agentSpeaking: Bool
    /// Wall clock of the first partner audio. Nil until the budget clock starts.
    public var startedAt: Date?
    /// Completed pauses only. The current pause is `pauseBeganAt`.
    public var pausedAccumulated: TimeInterval
    public var pauseBeganAt: Date?
    public var phrase: String
    public var phraseIsPartner: Bool
    public var activityIsLive: Bool
    public var leaving: Bool
    public var cap: TimeInterval

    public init(
        exercise: PracticeFormat.Kind,
        phase: ConversationPhase,
        floor: ConversationFloorOwner,
        agentSpeaking: Bool,
        startedAt: Date?,
        pausedAccumulated: TimeInterval = 0,
        pauseBeganAt: Date? = nil,
        phrase: String,
        phraseIsPartner: Bool,
        activityIsLive: Bool,
        leaving: Bool = false,
        cap: TimeInterval = 15 * 60
    ) {
        self.exercise = exercise
        self.phase = phase
        self.floor = floor
        self.agentSpeaking = agentSpeaking
        self.startedAt = startedAt
        self.pausedAccumulated = pausedAccumulated
        self.pauseBeganAt = pauseBeganAt
        self.phrase = phrase
        self.phraseIsPartner = phraseIsPartner
        self.activityIsLive = activityIsLive
        self.leaving = leaving
        self.cap = cap
    }
}

/// `orator://conversation/<uuid>`. Tap opens the app. It does not start a session.
public enum ConversationLiveActivityLink {
    public static let scheme = "orator"
    public static let host = "conversation"

    public static func url(for id: UUID) -> URL? {
        URL(string: "\(scheme)://\(host)/\(id.uuidString)")
    }

    public static func conversationID(from url: URL) -> UUID? {
        guard url.scheme == scheme, url.host == host else { return nil }
        let raw = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return UUID(uuidString: raw)
    }
}

/// Decides start, update, and end. The widget asks the same type what each surface may show.
public enum ConversationLiveActivityPolicy {
    public static let phraseLimit = 80
    public static let pausedLine = "Paused — still here."

    public static func command(for input: ConversationLiveActivityInput) -> ConversationLiveActivityCommand {
        guard input.exercise == .conversation else { return .none }
        guard keepsIsland(input), let startedAt = input.startedAt else {
            return input.activityIsLive ? .end : .none
        }
        let snapshot = snapshot(for: input, startedAt: startedAt)
        return input.activityIsLive ? .update(snapshot) : .start(snapshot)
    }

    /// The island does not show the live phrase. The Lock Screen is public, and the
    /// expanded row stays one line so the controls are not pushed into the corners.
    public static func showsPhrase(on surface: ConversationLiveActivitySurface) -> Bool {
        _ = surface
        return false
    }

    /// Pause matches the conversation screen: only while talking or already paused.
    public static func showsPause(
        on surface: ConversationLiveActivitySurface,
        phase: ConversationIslandPhase
    ) -> Bool {
        switch surface {
        case .expanded, .lockScreen:
            phase == .talking || phase == .paused
        case .compact, .minimal:
            false
        }
    }

    public static func showsStop(on surface: ConversationLiveActivitySurface) -> Bool {
        switch surface {
        case .expanded, .lockScreen: true
        case .compact, .minimal: false
        }
    }

    /// Landscape compact and minimal have to fit a 28pt circle, so the timer string goes.
    public static func showsTimer(
        on surface: ConversationLiveActivitySurface,
        limitedWidth: Bool
    ) -> Bool {
        switch surface {
        case .compact, .minimal:
            limitedWidth == false
        case .expanded, .lockScreen:
            true
        }
    }

    public static func orb(
        phase: ConversationPhase,
        floor: ConversationFloorOwner,
        agentSpeaking: Bool
    ) -> ConversationIslandOrb {
        if phase == .paused { return .paused }
        if agentSpeaking || (phase == .wrapping && floor == .partner) { return .speaking }
        return .listening
    }

    public static func truncatedPhrase(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > phraseLimit else { return trimmed }
        let end = trimmed.index(trimmed.startIndex, offsetBy: phraseLimit - 1)
        return String(trimmed[..<end]) + "…"
    }

    private static func keepsIsland(_ input: ConversationLiveActivityInput) -> Bool {
        guard input.leaving == false else { return false }
        switch input.phase {
        case .talking, .paused, .wrapping: return true
        case .idle, .countdown, .connecting, .report, .crisis, .dropped: return false
        }
    }

    private static func snapshot(
        for input: ConversationLiveActivityInput,
        startedAt: Date
    ) -> ConversationLiveActivitySnapshot {
        let timerStart = startedAt.addingTimeInterval(input.pausedAccumulated)
        let islandPhase: ConversationIslandPhase
        switch input.phase {
        case .paused: islandPhase = .paused
        case .wrapping: islandPhase = .wrapping
        default: islandPhase = .talking
        }
        return ConversationLiveActivitySnapshot(
            phase: islandPhase,
            orb: orb(phase: input.phase, floor: input.floor, agentSpeaking: input.agentSpeaking),
            timerStart: timerStart,
            timerEnd: timerStart.addingTimeInterval(input.cap),
            pauseTime: input.phase == .paused ? input.pauseBeganAt : nil,
            phrase: truncatedPhrase(input.phrase),
            phraseIsPartner: input.phraseIsPartner
        )
    }
}
