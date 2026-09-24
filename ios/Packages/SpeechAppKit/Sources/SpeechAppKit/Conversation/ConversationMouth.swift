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
    func close() async
    /// Linear mic level, 0…1, for the listen pill. 0 when the mouth has no meter.
    func currentInputLevel() async -> Float
}

extension ConversationMouth {
    public func currentInputLevel() async -> Float { 0 }
}

public enum MouthError: Error { case connectFailed }
