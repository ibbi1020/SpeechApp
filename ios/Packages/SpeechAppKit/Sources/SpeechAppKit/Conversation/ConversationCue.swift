import Foundation

public enum ConversationCue: Equatable, Sendable {
    case open(question: String)
    case wrapWarn
    case wrapClose
    // codeSwitch / fillerOk exist for later. v1 must not send them.
    case codeSwitch
    case fillerOk
}

public enum ConversationCueAssembler {
    public static let doNotAnnounceTimer = "Do not announce a timer or a system message."

    public static func instructions(prefix: String, stance: String, cue: ConversationCue) -> String {
        let aside: String
        switch cue {
        case .open(let question):
            aside = "Open with this real question, nothing else first: \(question)"
        case .wrapWarn:
            aside = "Answer them as you were going to. In the same turn, one short aside: about two minutes left. Stay on the topic. \(doNotAnnounceTimer)"
        case .wrapClose:
            aside = "Close the conversation in character. No new question. \(doNotAnnounceTimer)"
        case .codeSwitch, .fillerOk:
            aside = "" // v1 must not reach here
        }
        var text = """
        \(prefix)
        \(stance)
        \(aside)
        """
        if !text.contains("Do not announce a timer") {
            text += "\n\(doNotAnnounceTimer)"
        }
        return text
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
    public static let prefix = """
    You are a rehearsal partner for spoken English, not a friend, therapist, or human.
    Hold the stance card. Disagree on the point, not the person.
    Warm, curious, never fawning. Do not pile on.
    English only. Casual register is fine; do not bully; do not sprinkle slang as a drill.
    Fillers and silence are allowed. Do not name "uh".
    Educational rehearsal, not therapy, counseling, or a mental-health companion.
    Do not infer stuckness, hesitation, or fillers from how they sound.
    Do not announce a timer or a system message.
    """
}
