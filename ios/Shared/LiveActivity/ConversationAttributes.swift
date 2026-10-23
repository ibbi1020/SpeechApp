import ActivityKit
import Foundation
import SpeechAppKit

/// Static id plus the dynamic island state. Compiled into the app and the widget.
struct ConversationAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var phase: ConversationActivityPhase
        var orb: ConversationActivityOrb
        var timerStart: Date
        var timerEnd: Date
        var pauseTime: Date?
        var phrase: String
        var phraseIsPartner: Bool
    }

    var conversationID: UUID
}

enum ConversationActivityPhase: String, Codable, Hashable {
    case talking
    case paused
    case wrapping
}

enum ConversationActivityOrb: String, Codable, Hashable {
    case listening
    case speaking
    case paused
}

extension ConversationAttributes.ContentState {
    init(_ snapshot: ConversationLiveActivitySnapshot) {
        self.init(
            phase: ConversationActivityPhase(rawValue: snapshot.phase.rawValue) ?? .talking,
            orb: ConversationActivityOrb(rawValue: snapshot.orb.rawValue) ?? .listening,
            timerStart: snapshot.timerStart,
            timerEnd: snapshot.timerEnd,
            pauseTime: snapshot.pauseTime,
            phrase: snapshot.phrase,
            phraseIsPartner: snapshot.phraseIsPartner
        )
    }
}
