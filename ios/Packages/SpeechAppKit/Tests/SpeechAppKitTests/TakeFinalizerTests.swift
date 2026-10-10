import AVFoundation
import Foundation
import Testing
@testable import SpeechAppKit

@Suite("Take finalizer")
@MainActor
struct TakeFinalizerTests {
    @Test("saved take is audible, not silent")
    func savedTakeIsAudible() async throws {
        let input = try AudioProbe.fixture("voice_sentence")
        let (url, report) = try await finalize(input.samples, rate: input.sampleRate)
        defer { try? FileManager.default.removeItem(at: url) }
        let output = try AudioProbe.read(url)

        #expect(abs(output.duration - input.duration) < 0.5)
        #expect(output.rms > input.rms * 0.2, "saved rms \(output.rms) vs input \(input.rms)")
        #expect(report.outputPeak > 0.5)
    }

    @Test("quiet phone take is boosted to a listenable level")
    func quietTakeIsBoosted() async throws {
        let input = try AudioProbe.fixture("voice_sentence")
        // `.measurement` mode often records around −30 dBFS.
        let quiet = input.samples.map { $0 * 0.03 }
        let (url, report) = try await finalize(quiet, rate: input.sampleRate)
        defer { try? FileManager.default.removeItem(at: url) }
        let output = try AudioProbe.read(url)

        #expect(report.gain > 5)
        #expect(output.rms > input.rms * 0.3, "saved rms \(output.rms) vs original speech \(input.rms)")
    }

    @Test("normalizer caps gain and never clips")
    func normalizerLimits() {
        #expect(LoudnessNormalizer.gain(for: [0.0001, -0.0001]) == LoudnessNormalizer.maxGain)
        #expect(LoudnessNormalizer.gain(for: [0.95]) == 1)
        var samples: [Float] = [0.5, -0.5]
        LoudnessNormalizer.apply(gain: 4, to: &samples)
        #expect(samples == [1, -1])
    }

    /// Feeds samples through the recorder in mic-sized chunks, then finalizes.
    private func finalize(_ samples: [Float], rate: Double) async throws -> (URL, TakeFinalizer.Report) {
        let recorder = TakeRecorder()
        try recorder.start()
        let upsampled = AudioProbe.resample(samples, from: rate, to: 48_000)
        var offset = 0
        while offset < upsampled.count {
            let end = min(upsampled.count, offset + 1024)
            recorder.append(AudioChunk(samples: Array(upsampled[offset..<end]), sampleRate: 48_000, hostTime: 0))
            offset = end
        }
        let raw = try #require(recorder.stop())
        return try await TakeFinalizer.finalizeWithReport(rawCAF: raw)
    }
}

enum AudioProbe {
    struct Result {
        let samples: [Float]
        let sampleRate: Double
        var duration: Double { Double(samples.count) / sampleRate }
        var rms: Float {
            guard !samples.isEmpty else { return 0 }
            var sum: Float = 0
            for s in samples { sum += s * s }
            return (sum / Float(samples.count)).squareRoot()
        }
    }

    static func fixture(_ name: String) throws -> Result {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "wav"))
        return try read(url)
    }

    static func read(_ url: URL) throws -> Result {
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        let format = file.processingFormat
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length)) else {
            return Result(samples: [], sampleRate: format.sampleRate)
        }
        try file.read(into: buffer)
        let count = Int(buffer.frameLength)
        let samples = buffer.floatChannelData.map { Array(UnsafeBufferPointer(start: $0[0], count: count)) } ?? []
        return Result(samples: samples, sampleRate: format.sampleRate)
    }

    static func resample(_ samples: [Float], from: Double, to: Double) -> [Float] {
        guard abs(from - to) > 0.5, !samples.isEmpty else { return samples }
        let ratio = to / from
        let count = Int(Double(samples.count) * ratio)
        return (0..<count).map { i in
            let src = Double(i) / ratio
            let i0 = min(Int(src), samples.count - 1)
            let i1 = min(i0 + 1, samples.count - 1)
            let frac = Float(src - Double(i0))
            return samples[i0] + (samples[i1] - samples[i0]) * frac
        }
    }
}
