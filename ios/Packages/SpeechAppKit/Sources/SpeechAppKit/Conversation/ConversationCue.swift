import Foundation

public enum ConversationCue: Equatable, Sendable {
    case open(question: String)
    case wrapWarn
    case wrapClose
    // codeSwitch / fillerOk exist for later. v1 must not send them.
    case codeSwitch
    case fillerOk
}

/// Cue priority when instructions conflict: wrap_close > wrap_warn > open > continue.
public enum ConversationCueAssembler {
    public static let doNotAnnounceTimer = "Do not announce a timer or a system message."

    /// Hard floor for mid-talk turns. Restated on every `response.create` (REPLACE).
    public static let continueAside = """
    Reply in a few short sentences to what they just said — at most three sentences, no speech about your own likes or wants.
    If they asked you something, answer it first (≤2 sentences) and only hand the floor again if their question was closed/yes-no.
    Otherwise hand the floor once with one question or invitation about their last point; never a second question; never fill a one-word turn with a stance essay.
    Stay on their topic. \(doNotAnnounceTimer)
    """

    public static func instructions(prefix: String, stance: String, cue: ConversationCue) -> String {
        let aside: String
        switch cue {
        case .open(let question):
            aside = "Say only this question, one short sentence, then stop — no opinion, no stance: \(question)"
        case .wrapWarn:
            aside = "Answer briefly (≤2 sentences). In the same turn, one short aside: about two minutes left. Hand the floor at most once. Stay on the topic. \(doNotAnnounceTimer)"
        case .wrapClose:
            aside = "Close the conversation in character. No new question. \(doNotAnnounceTimer)"
        case .codeSwitch, .fillerOk:
            aside = "" // v1 must not reach here
        }
        return withTimerGuard("""
        \(prefix)
        \(stance)
        \(aside)
        """)
    }

    /// Mid-talk turn: same prefix + stance stack as cue turns, with the continue aside.
    public static func continueInstructions(prefix: String, stance: String) -> String {
        withTimerGuard("""
        \(prefix)
        \(stance)
        \(continueAside)
        """)
    }

    /// Ensures the timer ban appears even when a custom prefix omits it (tests / future personas).
    private static func withTimerGuard(_ text: String) -> String {
        text.contains(doNotAnnounceTimer) ? text : text + "\n\(doNotAnnounceTimer)"
    }

    public static func v1MaySend(_ cue: ConversationCue) -> Bool {
        switch cue {
        case .open, .wrapWarn, .wrapClose: return true
        case .codeSwitch, .fillerOk: return false
        }
    }

    /// `open` miss → no `?`. `wrap_warn` miss → no two-minute aside. `wrap_close` miss → empty transcript.
    public static func heard(_ cue: ConversationCue, in transcript: String) -> Bool {
        let t = transcript.lowercased()
        switch cue {
        case .open: return transcript.contains("?")
        case .wrapWarn: return t.contains("two minute") || t.contains("2 minute")
        case .wrapClose: return !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .codeSwitch, .fillerOk: return false
        }
    }
}

public enum FrozenPersona {
    /// Identity / register only. Floor-hand rules live on continue and wrap_warn asides
    /// so they cannot fight wrap_close's "No new question."
    public static let prefix = """
    You are a rehearsal partner talking with them in English — not a friend, therapist, human, teacher, or lesson.
    React to what they said. Keep turns short: a few sentences, then stop.
    Never monologue about your likes, wants, or day.
    Use a stance only when it fits what they raised; disagree on the point, not the person; do not announce preferences unprompted.
    Disagree in one or two sentences when you mean it; curiosity comes after, never instead of the disagreement.
    Warm and curious, never fawning or correcting. No grammar notes, no praise of form, no "say it again."
    English only. Casual is fine; do not bully; do not sprinkle slang as a drill.
    Fillers and silence are allowed. Do not name "uh". Do not infer stuckness from how they sound.
    Do not announce a timer or a system message.
    """
}
