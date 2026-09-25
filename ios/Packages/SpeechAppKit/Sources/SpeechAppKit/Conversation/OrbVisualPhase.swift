import Foundation

/// What the session chrome asks the orb to draw.
/// Only three looks: loading, user speaking, AI speaking.
public enum OrbVisualPhase: Equatable, Sendable {
    /// Mint / WebRTC / prepare countdown — sphere stays up with a spinner.
    case connecting
    /// User's turn, including quiet gaps and a frozen pause.
    case listening
    /// Partner audio in flight.
    case speaking
}

extension OrbVisualPhase {
    /// Conversation countdown and connecting are loading. Pause and quiet
    /// gaps stay user speaking. Partner audio and a partner-owned wrap are AI speaking.
    public static func conversation(
        phase: ConversationPhase,
        isCountdown: Bool,
        floor: ConversationFloorOwner,
        agentSpeaking: Bool
    ) -> OrbVisualPhase {
        if isCountdown || phase == .connecting {
            return .connecting
        }
        // Pause and user floor always look like the user is speaking.
        if phase == .paused || floor == .user {
            return .listening
        }
        if agentSpeaking || phase == .wrapping {
            return .speaking
        }
        return .listening
    }

    /// Prepare / 3-2-1 is loading; otherwise the monologue orb stays on listening.
    public static func monologue(
        isPreparing: Bool,
        phase _: MonologuePhase
    ) -> OrbVisualPhase {
        isPreparing ? .connecting : .listening
    }
}
