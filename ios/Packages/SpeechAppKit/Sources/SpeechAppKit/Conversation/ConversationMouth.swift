import Foundation

public enum MouthEvent: Equatable, Sendable {
    case sessionUpdated
    case speechStarted
    case speechStopped
    case audioDelta
    case responseDone(transcript: String)
    case disconnected
    case failed
}

public protocol ConversationMouth: AnyObject, Sendable {
    var events: AsyncStream<MouthEvent> { get }
    func connect(ephemeralKey: String) async throws
    func sendResponseCreate(instructions: String) async throws
    func updateTurnDetectionNull() async throws
    func close() async
}

public enum MouthError: Error { case connectFailed }
