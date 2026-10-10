import Foundation

/// Peak normalization for saved takes so quiet phone recordings are audible.
public enum LoudnessNormalizer {
    /// About −1 dBFS: loud without clipping after AAC.
    public static let targetPeak: Float = 0.89
    /// Cap at +24 dB so a near-silent take does not become pure hiss.
    public static let maxGain: Float = 16

    public static func gain(for samples: [Float]) -> Float {
        var peak: Float = 0
        for sample in samples {
            peak = max(peak, abs(sample))
        }
        guard peak > 0 else { return 1 }
        return min(maxGain, max(1, targetPeak / peak))
    }

    public static func apply(gain: Float, to samples: inout [Float]) {
        guard gain != 1 else { return }
        for index in samples.indices {
            samples[index] = max(-1, min(1, samples[index] * gain))
        }
    }
}
