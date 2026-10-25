import Foundation

/// When the reader has stopped talking, so the Done control can widen.
///
/// This watches the microphone clock only. The live underline is a separate
/// path and is not consulted.
public struct SpeechRest: Equatable, Sendable {
    /// Same wait the transcriber uses before it closes a turn (`smart_turn_timeout`).
    /// A breath or a period stays inside this, so the button does not open and shut
    /// on every sentence.
    public static let quietSeconds: TimeInterval = 3

    public private(set) var offersDone = false

    private var armed = false
    private var lastSpeechTime: TimeInterval?

    public init() {}

    public mutating func note(speaking: Bool, at time: TimeInterval) {
        if speaking {
            armed = true
            lastSpeechTime = time
            offersDone = false
            return
        }
        guard armed, let lastSpeechTime else {
            offersDone = false
            return
        }
        offersDone = time - lastSpeechTime >= Self.quietSeconds
    }

    /// Pause time does not count as quiet. The wait starts again at `time`.
    public mutating func hold(at time: TimeInterval) {
        guard armed else { return }
        lastSpeechTime = time
        offersDone = false
    }

    public mutating func reset() {
        offersDone = false
        armed = false
        lastSpeechTime = nil
    }
}
