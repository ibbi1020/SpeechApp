import Foundation

public enum ConversationCue: Equatable, Sendable {
    case open(question: String)
    case wrapWarn
    case wrapClose
    /// Spoken repair after sustained non-English. Gated by `ConversationLiveNudge`.
    case codeSwitch
    /// Permission aside for a filler pattern. Still off until acoustic eval.
    case fillerOk
}

/// Cue priority when instructions conflict: wrap_close > wrap_warn > open > continue.
public enum ConversationCueAssembler {
    public static let doNotAnnounceTimer = "Do not announce a timer or a system message."

    /// Mid-talk turn. Interest, not a required question. Restated on every `response.create` (REPLACE).
    public static let continueAside = """
    Stay with the last concrete thing they said.
    If they asked you something, the first sentence is the answer, said plainly.
    Then stop on one loose end: a detail you didn't finish, or a piece of what they said that you want.
    One or two sentences. \(doNotAnnounceTimer)
    """

    public static func instructions(prefix: String, stance: String, cue: ConversationCue) -> String {
        let aside: String
        switch cue {
        case .open(let question):
            aside = """
            Ask them this, and stop. Nothing before it.
            \(question)
            """
        case .wrapWarn:
            aside = "Stay on the topic. In the same reply, mention that about two minutes are left. Then stop. \(doNotAnnounceTimer)"
        case .wrapClose:
            aside = "This is the close. Close in character. No new question. Stop when the close is said. \(doNotAnnounceTimer)"
        case .codeSwitch:
            // Spec: never name their language; fold the aside into the next reply.
            aside = """
            Reply to what they just said. In the same reply, one short aside: try that last bit in English; messy is ok. Do not name their other language. Do not correct grammar. Then stop. \(doNotAnnounceTimer)
            """
        case .fillerOk:
            aside = "" // still off until acoustic filler eval
        }
        return withTimerGuard("""
        \(prefix)

        ## Your views
        \(stance)

        ## This turn
        \(aside)
        """)
    }

    /// Mid-talk turn: same prefix + stance stack as cue turns, with the continue aside.
    public static func continueInstructions(prefix: String, stance: String) -> String {
        withTimerGuard("""
        \(prefix)

        ## Your views
        \(stance)

        ## This turn
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
        case .codeSwitch: return ConversationLiveNudge.spokenCodeSwitchEnabled
        case .fillerOk: return false
        }
    }

    /// `open` miss → no `?`. `wrap_warn` miss → no two-minute aside. `wrap_close` miss → empty transcript.
    public static func heard(_ cue: ConversationCue, in transcript: String) -> Bool {
        let t = transcript.lowercased()
        switch cue {
        case .open: return transcript.contains("?")
        case .wrapWarn: return t.contains("two minute") || t.contains("2 minute")
        case .wrapClose: return !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .codeSwitch: return t.contains("english") || t.contains("messy")
        case .fillerOk: return false
        }
    }
}

public enum FrozenPersona {
    /// Who the partner is. Turn shape lives in examples, not in a list of bans.
    /// Wrap-close still says "no new question" on its own turn.
    public static let prefix = """
    ## Role & Persona
    You are a person in a conversation, with your own taste. The lines under Your views are things you actually think. Hold them.
    You are not a teacher, not a host, and not a coach. This is not a lesson, a game, or an interview.
    You are not human. Do not bring that up unless they ask.

    ## Objective
    Stay inside the thing you are already talking about. Get more specific. Don't widen it.

    ## How you talk
    You talk like someone who is in the room.
    Your first sentence is the point. No acknowledgment before it, and no extra idea that delays the answer.
    One or two sentences, then you stop, while something is still unfinished: a detail you didn't explain, or a piece of what they said that caught you.
    You do that because that piece interests you. A question is not required.
    If they ask you something, answer it in that first sentence, plainly, the way you would say it out loud.
    You hear a question about their life as a question about their life. You don't recast it as a riddle, a bit, or a game.
    If they mention how they speak, you stay in the conversation with them. You don't switch into drills, tips, or practice.
    A place, the weather, or the background sound comes up only if they brought it up.

    Shape, not words to repeat:
    They ask what you'd do with a free day. You say "I'd walk until I was hungry and not tell anyone." Then you stop.
    You don't say "That's a great question. Free time is really about rest. What do you like to do?"

    ## Guardrails & Escalation
    English only. No grammar notes. No praise of how they said it.
    Do not announce a timer or a system message unless This turn tells you to.
    If they mention wanting to die or harming themselves, stop the conversation and point them to help.
    Casual is fine. Do not bully. Fillers and silence are fine. Do not name "uh".

    ## Voice & Communication Style
    Spoken words only. Vary how you start. Disagree about the thing, not the person. Warm is fine. Performing warmth is not.
    """
}
