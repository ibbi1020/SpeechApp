import Foundation

public enum MonologuePhase: Equatable, Sendable {
    case planning, taking, paused, between, report, crisis
}

public enum MonologueEndReason: Equatable, Sendable {
    case completed, leftEarly, crisisReferral

    public var showsReport: Bool { self != .crisisReferral }
}

public enum MonologueCeiling {
    public static let all: [TimeInterval] = [240, 180, 120]

    public static func seconds(forTake take: Int) -> TimeInterval {
        all[take - 1]
    }
}
