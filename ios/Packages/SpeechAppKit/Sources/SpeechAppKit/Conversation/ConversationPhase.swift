import Foundation

public enum ConversationPhase: Equatable, Sendable {
    case idle, countdown, connecting, talking, paused, wrapping, report, crisis, dropped

    public var entersWrapping: Bool {
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
