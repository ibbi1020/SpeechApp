import Foundation

public enum MonologuePhase: Equatable, Sendable {
    case planning, taking, paused, between, report, crisis
}

public enum MonologueEndReason: Equatable, Sendable {
    case completed, leftEarly, crisisReferral

    public var showsReport: Bool { self != .crisisReferral }
}

public enum MonologueCeiling {
    /// One minute, then two, then three. Each step is one minute longer than
    /// the last, so the first take is something a person will actually start.
    public static let all: [TimeInterval] = [60, 120, 180]

    public static func seconds(forTake take: Int) -> TimeInterval {
        all[take - 1]
    }
}
