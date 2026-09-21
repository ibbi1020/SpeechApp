import Foundation

/// Whether an `AVAudioSession` route change should pause Conversation.
/// Volume 0 is not a route change and never pauses.
public enum ConversationRoutePause {
    /// `reason` is `AVAudioSession.RouteChangeReason.rawValue`.
    public static func shouldPause(reason: UInt) -> Bool {
        switch reason {
        case 2, 4: // oldDeviceUnavailable, override
            true
        default:
            false
        }
    }
}
