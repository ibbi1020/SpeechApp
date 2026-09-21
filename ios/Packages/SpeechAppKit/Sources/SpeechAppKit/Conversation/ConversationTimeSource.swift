import Foundation

public protocol ConversationTimeSource: AnyObject, Sendable {
    var now: TimeInterval { get }
}

public final class ControllableTimeSource: ConversationTimeSource, @unchecked Sendable {
    public var now: TimeInterval
    public init(now: TimeInterval = 0) { self.now = now }
    public func advance(_ delta: TimeInterval) { now += delta }
}

public final class SystemTimeSource: ConversationTimeSource, @unchecked Sendable {
    public init() {}
    public var now: TimeInterval { ProcessInfo.processInfo.systemUptime }
}
