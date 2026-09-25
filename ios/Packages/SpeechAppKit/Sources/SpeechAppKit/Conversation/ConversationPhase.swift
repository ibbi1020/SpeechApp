import Foundation

public enum ConversationPhase: Equatable, Sendable {
    case idle, countdown, connecting, talking, paused, wrapping, report, crisis, dropped

    public var entersWrapping: Bool {
        switch self {
        case .talking, .paused: return true
        default: return false
        }
    }

    /// Pause is live only while talking or already paused. Connecting keeps the
    /// button slot so the orb stays centered, but the control itself is hidden.
    public var showsPauseButton: Bool {
        switch self {
        case .talking, .paused: return true
        default: return false
        }
    }
}

public enum ConversationEndReason: Equatable, Sendable {
    case userStop, wrap, pauseTTL, drop, crisisReferral, configDrift

    public var speaksClose: Bool { self == .wrap }
}
