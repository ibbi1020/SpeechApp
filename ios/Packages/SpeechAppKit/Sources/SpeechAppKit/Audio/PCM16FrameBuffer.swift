import Foundation

/// Turns mic float chunks into 100 ms PCM16 little-endian frames at 16 kHz.
/// 100 ms at 16 kHz is 1,600 samples, which is 3,200 bytes.
public struct PCM16FrameBuffer: Sendable {
    public static let targetRate: Double = 16_000
    public static let samplesPerFrame = 1_600
    public static let bytesPerFrame = 3_200

    private var pending: [Float] = []

    public init() {}

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
        while pending.count >= Self.samplesPerFrame {
            let slice = pending.prefix(Self.samplesPerFrame)
            pending.removeFirst(Self.samplesPerFrame)
            frames.append(Self.pcm16(slice))
        }
        if partial, !pending.isEmpty {
            frames.append(Self.pcm16(pending))
            pending.removeAll(keepingCapacity: true)
        }
        return frames
    }

    private func resample(_ samples: [Float], from sampleRate: Double) -> [Float] {
        if abs(sampleRate - Self.targetRate) < 1 {
            return samples
        }
        let outCount = Int((Double(samples.count) * Self.targetRate / sampleRate).rounded(.down))
        guard outCount > 0 else { return [] }
        var output = [Float]()
        output.reserveCapacity(outCount)
        let step = sampleRate / Self.targetRate
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
