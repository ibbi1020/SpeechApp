import Foundation

/// Partner audio that finished playing, on the microphone file's clock.
public struct PartnerAudioSpan: Sendable, Equatable {
    public let start: TimeInterval
    public let sampleRate: Double
    public let samples: [Float]

    public init(start: TimeInterval, sampleRate: Double, samples: [Float]) {
        self.start = start
        self.sampleRate = sampleRate
        self.samples = samples
    }
}

/// Splices partner audio into a mic take without moving the clock.
///
/// A sample is replaced only when the mic around it is quiet, so a barge-in
/// stays yours and a cancelled stretch stays flat.
public enum ListenBackMix {
    /// RMS below this, over `quietWindowSeconds`, counts as silence.
    public static let quietRMS: Float = 0.02
    public static let quietWindowSeconds: TimeInterval = 0.02

    public static func mix(
        mic: [Float],
        micRate: Double,
        spans: [PartnerAudioSpan],
        timelineShift: TimeInterval
    ) -> [Float] {
        guard micRate > 0, !mic.isEmpty, !spans.isEmpty else { return mic }
        // Quiet is judged on the original mic. Voice processing leaves a residual
        // during the partner's turn that is louder than digital silence, so the
        // cutoff is a fraction of how loud the speaker actually got.
        let original = mic
        let threshold = max(speechLevel(original) * 0.35, 0.0001)
        let squares = prefixSquares(original)
        var out = mic
        for span in spans {
            splice(
                span,
                into: &out,
                squares: squares,
                micCount: original.count,
                micRate: micRate,
                timelineShift: timelineShift,
                threshold: threshold
            )
        }
        return out
    }

    /// Drops partner audio that had not reached the speaker by `heardThrough`.
    public static func trimming(_ spans: [PartnerAudioSpan], heardThrough: TimeInterval) -> [PartnerAudioSpan] {
        spans.compactMap { span in
            guard span.sampleRate > 0, !span.samples.isEmpty else { return nil }
            let spanEnd = span.start + Double(span.samples.count) / span.sampleRate
            if span.start >= heardThrough { return nil }
            if spanEnd <= heardThrough { return span }
            let keep = Int(((heardThrough - span.start) * span.sampleRate).rounded(.down))
            guard keep > 0 else { return nil }
            return PartnerAudioSpan(
                start: span.start,
                sampleRate: span.sampleRate,
                samples: Array(span.samples.prefix(keep))
            )
        }
    }

    private static func splice(
        _ span: PartnerAudioSpan,
        into output: inout [Float],
        squares: [Double],
        micCount: Int,
        micRate: Double,
        timelineShift: TimeInterval,
        threshold: Float
    ) {
        guard span.sampleRate > 0, !span.samples.isEmpty else { return }
        let shifted = span.start - timelineShift
        let partner = resample(span.samples, from: span.sampleRate, to: micRate)
        guard !partner.isEmpty else { return }

        var dest = Int((shifted * micRate).rounded(.down))
        var source = 0
        if dest < 0 {
            source = -dest
            dest = 0
        }
        guard source < partner.count, dest < output.count else { return }

        let count = min(partner.count - source, output.count - dest)
        for offset in 0..<count {
            let index = dest + offset
            guard isQuiet(squares: squares, index: index, micCount: micCount, micRate: micRate, threshold: threshold) else { continue }
            output[index] = partner[source + offset]
        }
    }

    /// Running sum of squares. `prefix[i + 1]` is the sum through `mic[i]`, in
    /// Double so a long take does not lose the latest window.
    private static func prefixSquares(_ mic: [Float]) -> [Double] {
        var prefix = [Double](repeating: 0, count: mic.count + 1)
        var sum = 0.0
        for index in mic.indices {
            let sample = Double(mic[index])
            sum += sample * sample
            prefix[index + 1] = sum
        }
        return prefix
    }

    /// How loud speech got, ignoring the quiet majority of a take.
    static func speechLevel(_ mic: [Float]) -> Float {
        guard !mic.isEmpty else { return 0 }
        let step = max(1, mic.count / 20_000)
        var peaks: [Float] = []
        peaks.reserveCapacity((mic.count / step) + 1)
        var index = 0
        while index < mic.count {
            peaks.append(abs(mic[index]))
            index += step
        }
        peaks.sort()
        let picked = min(peaks.count - 1, Int(Double(peaks.count - 1) * 0.98))
        return peaks[picked]
    }

    private static func isQuiet(
        squares: [Double],
        index: Int,
        micCount: Int,
        micRate: Double,
        threshold: Float
    ) -> Bool {
        let radius = max(0, Int((quietWindowSeconds * micRate / 2).rounded(.down)))
        let lo = max(0, index - radius)
        let hi = min(micCount, index + radius + 1)
        guard hi > lo else { return true }
        let mean = (squares[hi] - squares[lo]) / Double(hi - lo)
        guard mean > 0 else { return 0 < threshold }
        return sqrt(mean) < Double(threshold)
    }

    /// Linear resample. A constant stays that constant, so a tone lands intact.
    static func resample(_ samples: [Float], from: Double, to: Double) -> [Float] {
        guard from > 0, to > 0, !samples.isEmpty else { return [] }
        guard abs(from - to) > 0.5 else { return samples }
        let ratio = to / from
        let outCount = max(1, Int((Double(samples.count) * ratio).rounded()))
        var out = [Float](repeating: 0, count: outCount)
        let last = samples.count - 1
        for i in 0..<outCount {
            let src = Double(i) / ratio
            let i0 = min(last, Int(src))
            let i1 = min(last, i0 + 1)
            let frac = Float(src - Double(i0))
            let s0 = samples[i0]
            let s1 = samples[i1]
            out[i] = s0 + (s1 - s0) * frac
        }
        return out
    }
}
