import Foundation

/// Estimates how far a denoised signal lags the original by correlating
/// short RMS envelopes. Used to correct AUSoundIsolation's ~58–94 ms delay.
public enum DelayEstimator {
    /// Returns the delay in seconds of `delayed` relative to `reference`
    /// (positive means `delayed` starts later). Searches up to `maxDelaySeconds`.
    public static func delaySeconds(
        reference: [Float],
        delayed: [Float],
        sampleRate: Double,
        maxDelaySeconds: TimeInterval = 0.2,
        hop: Int = 160
    ) -> TimeInterval {
        guard sampleRate > 0, !reference.isEmpty, !delayed.isEmpty else { return 0 }
        let refEnv = envelope(reference, hop: hop)
        let delEnv = envelope(delayed, hop: hop)
        guard !refEnv.isEmpty, !delEnv.isEmpty else { return 0 }

        let maxLagHops = max(1, Int((maxDelaySeconds * sampleRate) / Double(hop)))
        var bestLag = 0
        var bestScore = -Double.infinity
        for lag in 0...maxLagHops {
            let score = correlation(refEnv, delEnv, lag: lag)
            if score > bestScore {
                bestScore = score
                bestLag = lag
            }
        }
        return Double(bestLag * hop) / sampleRate
    }

    private static func envelope(_ samples: [Float], hop: Int) -> [Float] {
        guard hop > 0 else { return [] }
        var out: [Float] = []
        out.reserveCapacity(samples.count / hop + 1)
        var i = 0
        while i < samples.count {
            let end = min(samples.count, i + hop)
            var sum: Float = 0
            for j in i..<end {
                let s = samples[j]
                sum += s * s
            }
            out.append(sqrt(sum / Float(end - i)))
            i += hop
        }
        return out
    }

    private static func correlation(_ a: [Float], _ b: [Float], lag: Int) -> Double {
        // Compare a[0...] with b[lag...]
        let n = min(a.count, max(0, b.count - lag))
        guard n > 8 else { return -Double.infinity }
        var sum = 0.0
        var sumA = 0.0
        var sumB = 0.0
        for i in 0..<n {
            let av = Double(a[i])
            let bv = Double(b[i + lag])
            sum += av * bv
            sumA += av * av
            sumB += bv * bv
        }
        let denom = sqrt(sumA * sumB)
        guard denom > 0 else { return -Double.infinity }
        return sum / denom
    }
}
