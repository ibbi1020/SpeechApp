import Foundation

/// When a partner-voice pick is allowed onto the wire.
///
/// The current sentence keeps the voice it started with. A pick during that
/// sentence is sent only after the server has finished the reply and the
/// speaker has played it out.
public struct VoiceSwitch: Equatable, Sendable {
    public private(set) var applied: String
    public private(set) var pending: String?
    private var responseOpen = false
    private var playing = false

    public init(applied: String) {
        self.applied = PartnerVoice.canonical(applied)
    }

    /// True while this reply is still being generated or is still coming out of the speaker.
    public var isSpeaking: Bool { responseOpen || playing }

    /// Voice to send now. Nil keeps the sentence that is already speaking.
    public mutating func select(_ id: String) -> String? {
        let resolved = PartnerVoice.canonical(id)
        if isSpeaking {
            pending = resolved
            return nil
        }
        pending = nil
        guard resolved != applied else { return nil }
        applied = resolved
        return resolved
    }

    public mutating func noteResponseStarted() {
        responseOpen = true
    }

    public mutating func notePlaybackStarted() {
        playing = true
    }

    public mutating func noteResponseFinished() {
        responseOpen = false
    }

    public mutating func notePlaybackFinished() {
        playing = false
    }

    /// Barge-in or cancel. The sentence stopped, even if buffers were dropped.
    public mutating func noteInterrupted() {
        responseOpen = false
        playing = false
    }

    /// Voice to send once the agent is quiet, if the user picked a different one.
    public mutating func flushIfIdle() -> String? {
        guard !isSpeaking, let pending else { return nil }
        self.pending = nil
        guard pending != applied else { return nil }
        applied = pending
        return applied
    }
}
