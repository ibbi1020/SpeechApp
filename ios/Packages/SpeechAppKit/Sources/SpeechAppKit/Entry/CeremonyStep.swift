import Foundation

/// Steps of the pre-session ceremony.
///
/// `note`, `purpose` and `speak` stay in the type so they can come back by being
/// added to `Ceremony.active`. They are not shown.
public enum CeremonyStep: String, Equatable, Sendable, CaseIterable {
    case breathe
    case note
    case purpose
    case exercise
    case speak
    case hum
}

public enum Ceremony {
    /// What the user walks through, in order.
    public static let active: [CeremonyStep] = [.exercise, .breathe, .hum]

    /// Defined, not shown. Putting one back is adding it to `active`.
    public static let benched: [CeremonyStep] = [.note, .purpose, .speak]

    public static var first: CeremonyStep { active[0] }

    public static func next(after step: CeremonyStep) -> CeremonyStep? {
        guard let index = active.firstIndex(of: step) else { return nil }
        let following = active.index(after: index)
        guard following < active.endIndex else { return nil }
        return active[following]
    }

    public static func previous(before step: CeremonyStep) -> CeremonyStep? {
        guard let index = active.firstIndex(of: step), index > active.startIndex else { return nil }
        return active[active.index(before: index)]
    }
}

/// Words on the ceremony. They name the action. They do not promise a result,
/// and they never tell the user to relax or calm down.
public enum CeremonyCopy {
    /// No "deep breath" here. Both source protocols carry an explicit
    /// anti-hyperventilation instruction, so the cue names the pace, not the depth.
    public static let breatheLine = "Follow the circle. It grows as you breathe in."
    public static let breatheSettle = "Get ready"
    public static let breatheIn = "Breathe in"
    public static let breatheOut = "Breathe out"
    public static let breatheButton = "Done"
    /// What they just did. The pace is still six a minute, four in and six out, but
    /// that number here reads as if the exercise was six breaths. It is one.
    public static let breatheRate = "One breath"

    public static let exerciseButton = "This one"

    /// Shown only when the room is loud enough to get into the recording.
    public static let roomLoud = "This room is loud."
    public static let roomLoudDetail = "It will get into what you say."
    /// The room fell back to a usable level while the warning was up.
    public static let roomClear = "Quieter now. Go ahead."
    public static let roomContinue = "Continue"
    public static let roomContinueAnyway = "Continue anyway"

    /// Shown before any sound plays. The breath is air for the glide, not a cue
    /// for nerves. "Ready" did not say that a tap starts the sound. "Listen" told
    /// people to stay quiet on the same screen that asked them to use their voice.
    public static let humReady = "Play the sound"
    public static let humWaiting = "Playing"
    public static let humBreath = "A sound plays when you tap. Breathe in, then let your voice go up and down with it."
}

/// Paced breathing at the resonance-frequency target.
///
/// Six breaths a minute is the standard target and 4 + 6 is the protocol used in the
/// literature, though the ratio itself is not established: 1:2 and 1:1 produced no
/// measurable HRV difference at this rate. One cycle is enough to slow the person
/// down, which is the job of this step. The shortest *tested* dose is five minutes,
/// so the length is inference and the pacing is not. See docs/scoping-entry-ritual.md.
public enum BreathPacing {
    /// Still, before the first inhale. Landing on a screen already mid-breath means
    /// missing that breath.
    public static let settle: Double = 3
    public static let inhale: Double = 4
    public static let exhale: Double = 6
    public static let cycles = 1

    public static var cycle: Double { inhale + exhale }
    public static var total: Double { cycle * Double(cycles) }
    /// Breaths per minute. 6, by construction.
    public static var rate: Double { 60 / cycle }
}

/// The timed breath sequence. Done is allowed only when this returns true.
///
/// SwiftUI often starts this task, cancels it, and starts it again as the step
/// appears. `Task.sleep` throws as soon as the task is cancelled. Treating that
/// as a finished wait would skip the breath and turn Done on.
public enum BreathRun {
    /// Waits for one part of the breath.
    /// False when the wait is cut short, so a cancelled run is not finished.
    public static func wait(_ seconds: Double) async -> Bool {
        do {
            try await Task.sleep(for: .seconds(seconds))
        } catch {
            return false
        }
        return Task.isCancelled == false
    }

    /// Settle, then the inhale and the exhale. True means that breath finished.
    public static func finished() async -> Bool {
        guard await wait(BreathPacing.settle) else { return false }
        for _ in 0 ..< BreathPacing.cycles {
            guard await wait(BreathPacing.inhale) else { return false }
            guard await wait(BreathPacing.exhale) else { return false }
        }
        return Task.isCancelled == false
    }
}

/// Semi-occluded vocal tract exercises that need no straw and no water.
///
/// Two from each of the two physiologically distinct families found by
/// electroglottography: steady single-source, and fluctuating dual-source. No single
/// exercise is established as best, so rotating is defensible on mechanism rather
/// than only on novelty.
public enum VocalClip: String, Equatable, Sendable, CaseIterable {
    case hum
    case nasal
    case lipTrill
    case tongueTrill

    /// Steady exercises hold one source. Fluctuating ones add a second, vibrating one.
    public var isFluctuating: Bool {
        switch self {
        case .hum, .nasal: false
        case .lipTrill, .tongueTrill: true
        }
    }

    /// Shown while the sound plays. The mouth, and that the pitch moves.
    /// "Along" and "sing it back" never said whether to wait, copy, or join in.
    public var line: String {
        switch self {
        case .hum: "Lips closed, up then down."
        case .nasal: "Stay on \u{201C}ng\u{201D}, up then down."
        case .lipTrill: "Lips buzzing, up then down."
        case .tongueTrill: "Tongue rolling, up then down."
        }
    }

    /// Shown before the sound. The mouth only. The glide and the tap live on
    /// `CeremonyCopy.humBreath`, because nothing is playing yet to match.
    public var explain: String {
        switch self {
        case .hum: "Hum on \u{201C}mmm\u{201D}, lips closed."
        case .nasal: "Hold \u{201C}ng\u{201D}, like the end of \u{201C}sing\u{201D}."
        case .lipTrill: "Buzz your lips, like \u{201C}brrr\u{201D}."
        case .tongueTrill: "Roll your tongue, like \u{201C}rrrr\u{201D}."
        }
    }

    /// Ten seconds. Twenty ran people out of breath.
    public static let seconds: Double = 10

    /// Walks the list so the exercise differs run to run.
    public static func next(after previous: VocalClip?) -> VocalClip {
        guard let previous, let index = allCases.firstIndex(of: previous) else {
            return allCases[0]
        }
        return allCases[(index + 1) % allCases.count]
    }
}

/// Where the vocal-copy step is. Sound does not start until the user arms it.
public enum HumPhase: Equatable, Sendable {
    case explain
    case playing
    case finished
}

public enum CeremonyAdvance: Equatable, Sendable {
    /// Move to the next ceremony step.
    case step
    /// Start the siren. Stays on the hum step.
    case armHum
    /// Leave the ceremony and open the chosen exercise.
    case start(PracticeFormat.Kind)
}

public struct CeremonyControl: Equatable, Sendable {
    public let title: String
    public let isEnabled: Bool
    public let advance: CeremonyAdvance

    public init(title: String, isEnabled: Bool, advance: CeremonyAdvance) {
        self.title = title
        self.isEnabled = isEnabled
        self.advance = advance
    }
}

public enum CeremonyControls {
    /// The pinned button for one step. A spent conversation month is stopped here,
    /// before the hum, so the user is not walked to a control that cannot start.
    /// The pinned button while the loud-room warning is up. Copy follows the
    /// button band, which has hysteresis. The field color does not.
    public static func roomWarning(warning: Bool) -> CeremonyControl {
        CeremonyControl(
            title: warning ? CeremonyCopy.roomContinueAnyway : CeremonyCopy.roomContinue,
            isEnabled: true,
            advance: .step
        )
    }

    public static func control(
        step: CeremonyStep,
        chosen: PracticeFormat.Kind,
        budget: ConversationBudgetSnapshot,
        breatheDone: Bool = false,
        humPhase: HumPhase = .explain,
        roomReady: Bool = false
    ) -> CeremonyControl {
        switch step {
        case .breathe:
            return CeremonyControl(
                title: CeremonyCopy.breatheButton,
                isEnabled: breatheDone,
                advance: .step
            )
        case .exercise:
            if chosen == .conversation, budget.startEnabled == false {
                let blocked = PracticeFormat.startControl(for: .conversation, budget: budget)
                return CeremonyControl(title: blocked.title, isEnabled: false, advance: .step)
            }
            return CeremonyControl(
                title: CeremonyCopy.exerciseButton,
                isEnabled: roomReady,
                advance: .step
            )
        case .hum:
            switch humPhase {
            case .explain:
                return CeremonyControl(title: CeremonyCopy.humReady, isEnabled: true, advance: .armHum)
            case .playing:
                return CeremonyControl(title: CeremonyCopy.humWaiting, isEnabled: false, advance: .start(chosen))
            case .finished:
                let start = PracticeFormat.startControl(for: chosen, budget: budget)
                return CeremonyControl(title: start.title, isEnabled: start.isEnabled, advance: .start(chosen))
            }
        case .note, .purpose, .speak:
            return CeremonyControl(title: "", isEnabled: false, advance: .step)
        }
    }
}

/// One saved session, reduced to what the proposal needs.
public struct PracticeStamp: Equatable, Sendable {
    public var format: RecordingManifest.Format
    public var createdAt: Date

    public init(format: RecordingManifest.Format, createdAt: Date) {
        self.format = format
        self.createdAt = createdAt
    }
}

public struct WeeklyPracticeCounts: Equatable, Sendable {
    public var reading: Int
    public var monologue: Int
    public var conversation: Int

    public init(reading: Int = 0, monologue: Int = 0, conversation: Int = 0) {
        self.reading = reading
        self.monologue = monologue
        self.conversation = conversation
    }

    public var total: Int { reading + monologue + conversation }

    public func count(for kind: PracticeFormat.Kind) -> Int {
        switch kind {
        case .reading: reading
        case .monologue: monologue
        case .conversation: conversation
        }
    }
}

public struct ExerciseOffer: Equatable, Sendable {
    public let proposed: PracticeFormat.Kind
    /// The other two, in reading / monologue / conversation order.
    public let alternates: [PracticeFormat.Kind]

    public init(proposed: PracticeFormat.Kind, alternates: [PracticeFormat.Kind]) {
        self.proposed = proposed
        self.alternates = alternates
    }
}

public enum ExerciseOfferMaker {
    /// Last 7 days, measured back from `now`. Not a calendar week.
    public static let window: TimeInterval = 7 * 24 * 60 * 60

    public static func counts(of stamps: [PracticeStamp], now: Date) -> WeeklyPracticeCounts {
        let cutoff = now.addingTimeInterval(-window)
        var counts = WeeklyPracticeCounts()
        for stamp in stamps where stamp.createdAt >= cutoff {
            switch stamp.format {
            case .reading: counts.reading += 1
            case .monologue: counts.monologue += 1
            case .conversation: counts.conversation += 1
            }
        }
        return counts
    }

    /// The least-practised exercise. Ties break toward conversation, then monologue,
    /// then reading, so an empty week opens on the exercise the product is for.
    /// Conversation is left out when the month is spent.
    public static func offer(
        counts: WeeklyPracticeCounts,
        conversationAvailable: Bool
    ) -> ExerciseOffer {
        let preference: [PracticeFormat.Kind] = [.conversation, .monologue, .reading]
        let eligible = preference.filter { kind in
            kind != .conversation || conversationAvailable
        }
        let proposed = eligible.min { lhs, rhs in
            let left = counts.count(for: lhs)
            let right = counts.count(for: rhs)
            if left != right { return left < right }
            let leftRank = preference.firstIndex(of: lhs) ?? 0
            let rightRank = preference.firstIndex(of: rhs) ?? 0
            return leftRank < rightRank
        } ?? .monologue
        let alternates = PracticeFormat.all.map(\.kind).filter { $0 != proposed }
        return ExerciseOffer(proposed: proposed, alternates: alternates)
    }

    /// The week's history, but only where it explains something. Only the app's own
    /// proposal was produced by the history, so only it gets the citation; once the
    /// user picks something else the sentence would be about an exercise they are not
    /// looking at. Nil means say nothing.
    public static func history(
        for kind: PracticeFormat.Kind,
        counts: WeeklyPracticeCounts,
        proposed: PracticeFormat.Kind
    ) -> String? {
        guard kind == proposed, counts.total > 0 else { return nil }
        let heavy = heaviest(counts)
        let heavyCount = counts.count(for: heavy)
        let own = counts.count(for: kind)
        if heavy != kind, heavyCount > own {
            return sentence(heavy, count: heavyCount)
        }
        return sentence(kind, count: own)
    }

    private static func heaviest(_ counts: WeeklyPracticeCounts) -> PracticeFormat.Kind {
        var best = PracticeFormat.Kind.reading
        for kind in PracticeFormat.Kind.allCases {
            if counts.count(for: kind) > counts.count(for: best) {
                best = kind
            }
        }
        return best
    }

    private static func sentence(_ kind: PracticeFormat.Kind, count: Int) -> String {
        let verb: String
        switch kind {
        case .reading: verb = "read"
        case .monologue: verb = "talked"
        case .conversation: verb = "rehearsed"
        }
        let times = count == 1 ? "time" : "times"
        return "You've \(verb) \(count) \(times) this week."
    }
}
