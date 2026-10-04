import Foundation

public enum MouthEvent: Equatable, Sendable {
    /// Data channel is open and the opening cue may be sent. Clock stays off.
    case ready
    case sessionUpdated
    case speechStarted
    case speechStopped
    /// Partner has started a response (data-channel `response.created`).
    case responseStarted
    case audioDelta
    /// Accumulated partner transcript for the live stage. Empty strings are ignored.
    case partnerCaption(String)
    case responseDone(transcript: String)
    /// Mic activity while a barge-in is still held (orb only — not a turn).
    case interruptHeard
    /// Held barge-in ended before commit (orb returns the floor).
    case interruptDropped
    case disconnected
    case failed
    case configDrift
}

public protocol ConversationMouth: AnyObject, Sendable {
    var events: AsyncStream<MouthEvent> { get }
    /// Caption↔audio JSONL for this live mouth, if instrumentation is on.
    var captionSyncLogURL: URL? { get }
    /// Warm audio session, peer connection, and ICE during the countdown. No-op by default.
    func prepare() async throws
    func connect(ephemeralKey: String) async throws
    func sendResponseCreate(instructions: String) async throws
    func updateTurnDetectionNull() async throws
    /// Cancel the in-flight partner response (client barge-in). No-op when idle.
    func cancelResponse() async throws
    func close() async
    /// Linear mic level, 0…1, for the listen pill and barge-in sustain check. 0 when unavailable.
    func currentInputLevel() async -> Float
    /// Partner playback level, 0…1, for the speak orb. 0 when unavailable.
    func currentOutputLevel() async -> Float
}

extension ConversationMouth {
    public var captionSyncLogURL: URL? { nil }
    public func prepare() async throws {}
    public func currentInputLevel() async -> Float { 0 }
    public func currentOutputLevel() async -> Float { 0 }
    public func cancelResponse() async throws {}
}

public enum MouthError: Error { case connectFailed }
