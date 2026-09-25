import Foundation

/// Client-side barge-in while the partner is speaking.
/// Server `interrupt_response` stays off; echo and short coughs are held until
/// mic level stays above the echo floor for `sustainSeconds`, then we cancel.
public struct BargeInGate: Sendable {
    public static let sustainSeconds: TimeInterval = 0.3
    public static let echoFloor: Float = 0.05

    public enum Action: Equatable, Sendable {
        /// Forward the event to the session immediately.
        case passThrough
        /// Agent owns the floor; keep listening for a real barge-in.
        case hold
        /// Sustained loud speech — cancel the partner response, then forward `speechStarted`.
        case commitCancel
        /// Blip ended before sustain — do not forward any speech events.
        case swallow
    }

    public private(set) var agentSpeaking = false
    private var pendingSpeech = false
    private var loudAccumulated: TimeInterval = 0
    private var lastTickAt: TimeInterval?

    public init() {}

    public mutating func noteAgentAudio() {
        agentSpeaking = true
    }

    /// Partner finished. If speech was held, release it as `passThrough` so the
    /// session can take the floor without a cancel.
    @discardableResult
    public mutating func noteResponseDone() -> Action? {
        agentSpeaking = false
        guard pendingSpeech else { return nil }
        clearHold()
        return .passThrough
    }

    public mutating func onSpeechStarted() -> Action {
        guard agentSpeaking else { return .passThrough }
        beginHold()
        return .hold
    }

    public mutating func onSpeechStopped() -> Action {
        guard pendingSpeech else { return .passThrough }
        clearHold()
        return .swallow
    }

    /// Poll while holding. Returns `commitCancel` once level stays above the floor
    /// for `sustainSeconds`, otherwise `hold`.
    public mutating func tick(now: TimeInterval, level: Float) -> Action {
        guard pendingSpeech, agentSpeaking else { return .hold }
        if let last = lastTickAt {
            let dt = max(0, now - last)
            if level >= Self.echoFloor {
                loudAccumulated += dt
            } else {
                loudAccumulated = 0
            }
        }
        lastTickAt = now
        guard loudAccumulated >= Self.sustainSeconds else { return .hold }
        clearHold()
        agentSpeaking = false
        return .commitCancel
    }

    private mutating func beginHold() {
        pendingSpeech = true
        loudAccumulated = 0
        lastTickAt = nil
    }

    private mutating func clearHold() {
        pendingSpeech = false
        loudAccumulated = 0
        lastTickAt = nil
    }
}
