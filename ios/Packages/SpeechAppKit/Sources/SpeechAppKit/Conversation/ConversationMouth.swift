import Foundation

public enum MouthEvent: Equatable, Sendable {
    case sessionUpdated
    case speechStarted
    case speechStopped
    case audioDelta
    case responseDone(transcript: String)
    case disconnected
    case failed
    case configDrift
}

public protocol ConversationMouth: AnyObject, Sendable {
    var events: AsyncStream<MouthEvent> { get }
    func connect(ephemeralKey: String) async throws
    func sendResponseCreate(instructions: String) async throws
    func updateTurnDetectionNull() async throws
    /// Cancel the in-flight partner response (client barge-in). No-op when idle.
    func cancelResponse() async throws
    func close() async
    /// Linear mic level, 0…1, for the listen pill and barge-in sustain check. 0 when unavailable.
    func currentInputLevel() async -> Float
}

extension ConversationMouth {
    public func currentInputLevel() async -> Float { 0 }
    public func cancelResponse() async throws {}
}

public enum MouthError: Error { case connectFailed }
