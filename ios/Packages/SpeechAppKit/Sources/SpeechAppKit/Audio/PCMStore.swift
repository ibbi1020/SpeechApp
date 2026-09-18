import Foundation

/// In-memory PCM capture for specialized sound analysis (Slice B).
/// Process-and-delete: call `secureClear()` after building the report.
public final class PCMStore: @unchecked Sendable {
    public private(set) var sampleRate: Double = 16_000
    private var samples: [Float] = []
    private let lock = NSLock()

    public init() {}

    public var sampleCount: Int {
        lock.lock(); defer { lock.unlock() }
        return samples.count
    }

    public var durationSeconds: TimeInterval {
        lock.lock(); defer { lock.unlock() }
        guard sampleRate > 0 else { return 0 }
        return Double(samples.count) / sampleRate
    }

    public func append(_ chunk: AudioChunk) {
        lock.lock()
        defer { lock.unlock() }
        if samples.isEmpty {
            sampleRate = chunk.sampleRate
        }
        samples.append(contentsOf: chunk.samples)
    }

    /// Slice by relative progress through the capture (0...1). Used until per-word
    /// Apple timestamps are plumbed into alignment events.
    public func slice(startFraction: Double, endFraction: Double) -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        guard !samples.isEmpty else { return [] }
        let start = max(0, min(1, startFraction))
        let end = max(start, min(1, endFraction))
        let i0 = Int(Double(samples.count) * start)
        let i1 = Int(Double(samples.count) * end)
        guard i1 > i0 else { return [] }
        return Array(samples[i0..<i1])
    }

    public func allSamples() -> [Float] {
        lock.lock(); defer { lock.unlock() }
        return samples
    }

    public func secureClear() {
        lock.lock()
        defer { lock.unlock() }
        for i in samples.indices {
            samples[i] = 0
        }
        samples.removeAll(keepingCapacity: false)
    }
}
