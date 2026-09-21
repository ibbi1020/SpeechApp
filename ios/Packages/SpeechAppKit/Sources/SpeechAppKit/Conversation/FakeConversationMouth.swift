import Foundation

public final class FakeConversationMouth: ConversationMouth, @unchecked Sendable {
    public let events: AsyncStream<MouthEvent>
    private let continuation: AsyncStream<MouthEvent>.Continuation
    public private(set) var responseCreates: [String] = []
    public private(set) var didClose = false
    public private(set) var turnDetectionNulled = false
    public var connectShouldFail = false

    public init() {
        let pair = AsyncStream<MouthEvent>.makeStream(bufferingPolicy: .unbounded)
        events = pair.stream
        continuation = pair.continuation
    }

    public func connect(ephemeralKey: String) async throws {
        if connectShouldFail { throw MouthError.connectFailed }
        // Do not auto-yield. Tests and the App event pump call session.handle.
    }

    public func sendResponseCreate(instructions: String) async throws {
        responseCreates.append(instructions)
    }

    public func updateTurnDetectionNull() async throws {
        turnDetectionNulled = true
    }

    public func close() async {
        didClose = true
        continuation.finish()
    }

    public func emit(_ event: MouthEvent) {
        continuation.yield(event)
    }
}
