import AVFoundation
import Foundation
import Testing

@Suite("Ambient beds sound like their places")
struct AmbientMusicalityTests {
    @Test("beach is waves, not a music loop")
    func beachIsNotMusic() throws {
        let beach = try Self.samples(named: "ambient-beach")
        let score = Self.musicalScore(samples: beach, sampleRate: 24_000)
        #expect(score < 2, "beach musical score \(score) — a tone loop, not surf")
    }

    @Test("rain stays noise-like")
    func rainIsNotMusic() throws {
        let rain = try Self.samples(named: "ambient-rain")
        let score = Self.musicalScore(samples: rain, sampleRate: 24_000)
        #expect(score < 2, "rain musical score \(score)")
    }

    private static func samples(named name: String) throws -> [Float] {
        let url = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .appending(path: "../../../../App/Resources/Ambient/\(name).caf")
            .standardizedFileURL
        let file = try AVAudioFile(forReading: url)
        let capacity = AVAudioFrameCount(file.length)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: capacity),
              let channel = buffer.floatChannelData?[0]
        else {
            throw CocoaError(.fileReadCorruptFile)
        }
        try file.read(into: buffer)
        return Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
    }

    /// Median harmonic prominence. Music sits well above 2. Surf, rain, and room tone sit near 1.
    static func musicalScore(samples: [Float], sampleRate: Double) -> Double {
        let window = Int(sampleRate)
        guard samples.count >= window else { return 0 }
        var scores: [Double] = []
        var start = 0
        while start + window <= samples.count {
            scores.append(harmonicProminence(samples: samples, start: start, count: window, sampleRate: sampleRate))
            start += window
        }
        scores.sort()
        return scores[scores.count / 2]
    }

    private static func harmonicProminence(
        samples: [Float],
        start: Int,
        count: Int,
        sampleRate: Double
    ) -> Double {
        let windowed: [Float] = (0..<count).map { index in
            let hann = 0.5 - 0.5 * cos(2 * .pi * Float(index) / Float(count - 1))
            return samples[start + index] * hann
        }
        var bestPower = 0.0
        var fundamental = 80.0
        var frequency = 80.0
        while frequency <= 400 {
            let power = goertzel(windowed, frequency: frequency, sampleRate: sampleRate)
            if power > bestPower {
                bestPower = power
                fundamental = frequency
            }
            frequency += 4
        }
        var peak = 0.0
        var floor = 0.0
        var harmonic = 2
        while harmonic <= 5 {
            let target = fundamental * Double(harmonic)
            if target > 2_000 { break }
            let center = goertzel(windowed, frequency: target, sampleRate: sampleRate)
            let neighbors = [-40.0, -24.0, 24.0, 40.0].map {
                goertzel(windowed, frequency: target + $0, sampleRate: sampleRate)
            }.sorted()
            peak += center
            floor += (neighbors[1] + neighbors[2]) / 2
            harmonic += 1
        }
        return peak / (floor + 1e-9)
    }

    private static func goertzel(_ samples: [Float], frequency: Double, sampleRate: Double) -> Double {
        let omega = 2 * Double.pi * frequency / sampleRate
        let coefficient = 2 * cos(omega)
        var previous = 0.0
        var older = 0.0
        for sample in samples {
            let next = Double(sample) + coefficient * previous - older
            older = previous
            previous = next
        }
        return previous * previous + older * older - coefficient * previous * older
    }
}
