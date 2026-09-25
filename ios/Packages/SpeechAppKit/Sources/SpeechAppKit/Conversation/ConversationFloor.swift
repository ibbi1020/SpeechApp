import Foundation

/// Who owns the orb during a live conversation.
/// Barge-in hold flips to the user immediately; a swallowed blip returns the floor.
public enum ConversationFloorOwner: Equatable, Sendable {
    case partner
    case user
}

public struct ConversationFloor: Equatable, Sendable {
    public private(set) var owner: ConversationFloorOwner = .partner

    public init(owner: ConversationFloorOwner = .partner) {
        self.owner = owner
    }

    public mutating func apply(_ event: MouthEvent) {
        switch event {
        case .speechStarted, .interruptHeard:
            owner = .user
        case .speechStopped, .interruptDropped:
            owner = .partner
        default:
            break
        }
    }
}
