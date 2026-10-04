import Foundation

/// Turns mic float chunks into 100 ms PCM16 little-endian frames.
/// Default is 16 kHz (STT). Pass `rate: 24_000` for Grok speech-to-speech.
public struct PCM16FrameBuffer: Sendable {
    public static let targetRate: Double = 16_000
    public static let samplesPerFrame = 1_600
    public static let bytesPerFrame = 3_200
    private static let frameDurationSeconds = 0.1

    private let rate: Double
    private let frameSamples: Int
    private var pending: [Float] = []

    public init(rate: Double = Self.targetRate) {
        self.rate = rate
        frameSamples = max(1, Int((rate * Self.frameDurationSeconds).rounded()))
    }

    public mutating func append(samples: [Float], sampleRate: Double) -> [Data] {
        guard sampleRate > 0, !samples.isEmpty else { return [] }
        pending.append(contentsOf: resample(samples, from: sampleRate))
        return drain(partial: false)
    }

    /// Send whatever is left, even if it is shorter than 100 ms, so the last words are not dropped.
    public mutating func flush() -> [Data] {
        drain(partial: true)
    }

    private mutating func drain(partial: Bool) -> [Data] {
        var frames: [Data] = []
        while pending.count >= frameSamples {
            let slice = pending.prefix(frameSamples)
            pending.removeFirst(frameSamples)
            frames.append(Self.pcm16(slice))
        }
        if partial, !pending.isEmpty {
            frames.append(Self.pcm16(pending))
            pending.removeAll(keepingCapacity: true)
        }
        return frames
    }

    private func resample(_ samples: [Float], from sampleRate: Double) -> [Float] {
        if abs(sampleRate - rate) < 1 {
            return samples
        }
        let outCount = Int((Double(samples.count) * rate / sampleRate).rounded(.down))
        guard outCount > 0 else { return [] }
        var output = [Float]()
        output.reserveCapacity(outCount)
        let step = sampleRate / rate
        for index in 0..<outCount {
            let position = Double(index) * step
            let left = Int(position)
            let fraction = Float(position - Double(left))
            let right = min(left + 1, samples.count - 1)
            let sample = samples[left] * (1 - fraction) + samples[right] * fraction
            output.append(sample)
        }
        return output
    }

    static func pcm16<S: Sequence>(_ samples: S) -> Data where S.Element == Float {
        var data = Data()
        for sample in samples {
            let clamped = min(1, max(-1, sample))
            let scaled = clamped < 0 ? clamped * 32_768 : clamped * 32_767
            var value = Int16(scaled).littleEndian
            withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
        }
        return data
    }
}
