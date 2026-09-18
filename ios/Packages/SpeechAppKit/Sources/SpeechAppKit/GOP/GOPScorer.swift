import Foundation

public enum GOPAssessment: Equatable, Sendable {
    case notAssessed
    case poorSound
    case ok
}

public protocol GOPScorer: Sendable {
    func score(scriptWord: ScriptWord, pcmSlice: [Float]) async -> GOPAssessment
}

/// Explicit Slice A stub — every word is `.notAssessed`.
public struct NotAssessedGOPScorer: GOPScorer {
    public init() {}

    public func score(scriptWord: ScriptWord, pcmSlice: [Float]) async -> GOPAssessment {
        .notAssessed
    }
}

/// Slice B seam: refuses to invent scores from Apple’s transcript.
/// Requires PCM + canonical phones; still returns `.notAssessed` until a specialized
/// on-device acoustic model (CTC/GOP — not Apple SpeechAnalyzer) is plugged in.
/// Intentionally does **not** grade silence/energy heuristics as “poor sound” —
/// fake negatives hurt anxious users more than an honest “not assessed.”
public struct SpecializedSoundScorer: GOPScorer {
    public init() {}

    public func score(scriptWord: ScriptWord, pcmSlice: [Float]) async -> GOPAssessment {
        let phones = scriptWord.resolvedPhones
        guard !pcmSlice.isEmpty, !phones.isEmpty else {
            return .notAssessed
        }
        // Reserved: specialized CTC/GOP model inference on `pcmSlice` vs `phones`.
        return .notAssessed
    }
}
