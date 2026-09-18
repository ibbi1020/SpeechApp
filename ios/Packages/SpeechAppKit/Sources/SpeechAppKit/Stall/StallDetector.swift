import Foundation

/// Cheap RMS-energy VAD stall detector (not Apple SpeechDetector).
public final class StallDetector: @unchecked Sendable {
    public struct Configuration: Sendable, Equatable {
        public var silenceTimeout: TimeInterval
        public var energyThreshold: Float
        /// Require this much speech energy before stall detection arms (avoids pre-start false nudges).
        public var armAfterSpeech: Bool

        public init(
            silenceTimeout: TimeInterval = 4.5,
            energyThreshold: Float = 0.01,
            armAfterSpeech: Bool = true
        ) {
            self.silenceTimeout = silenceTimeout
            self.energyThreshold = energyThreshold
            self.armAfterSpeech = armAfterSpeech
        }
    }

    public private(set) var isStalled: Bool = false
    public private(set) var isArmed: Bool = false

    private let configuration: Configuration
    private var lastSpeechTime: TimeInterval = 0
    private var currentTime: TimeInterval = 0
    private var dismissedUntilSpeech: Bool = false

    public init(configuration: Configuration = .init()) {
        self.configuration = configuration
        self.isArmed = !configuration.armAfterSpeech
    }

    /// Feed PCM float samples and the absolute clock time for this buffer.
    /// Returns `true` when a stall nudge should be shown (edge-triggered).
    @discardableResult
    public func process(samples: [Float], at time: TimeInterval) -> Bool {
        currentTime = time
        let rms = Self.rms(samples)
        let speaking = rms >= configuration.energyThreshold

        if speaking {
            lastSpeechTime = time
            isArmed = true
            dismissedUntilSpeech = false
            if isStalled {
                isStalled = false
            }
            return false
        }

        guard isArmed, !dismissedUntilSpeech else { return false }

        let silentFor = time - lastSpeechTime
        if silentFor >= configuration.silenceTimeout {
            if !isStalled {
                isStalled = true
                return true
            }
        }
        return false
    }

    /// User dismissed the nudge; do not re-fire until speech resumes.
    public func dismiss() {
        isStalled = false
        dismissedUntilSpeech = true
    }

    public func reset() {
        isStalled = false
        isArmed = !configuration.armAfterSpeech
        lastSpeechTime = 0
        currentTime = 0
        dismissedUntilSpeech = false
    }

    public static func rms(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        var sum: Float = 0
        for sample in samples {
            sum += sample * sample
        }
        return sqrt(sum / Float(samples.count))
    }
}
