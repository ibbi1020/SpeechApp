import AVFoundation
import Foundation

public enum TakeFinalizerError: Error {
    case empty
    case encodeFailed
}

/// Denoise (AUSoundIsolation) → delay fix → AAC 16 kHz mono 32 kbps.
public enum TakeFinalizer {
    public static let outputSampleRate: Double = 16_000
    public static let bitRate = 32_000

    /// What happened to one take, for logs and tests.
    public struct Report: Sendable, Equatable {
        public let inputPeak: Float
        public let usedDenoise: Bool
        public let denoiseDelaySeconds: TimeInterval
        public let gain: Float
        public let outputPeak: Float
    }

    /// Returns a local `.m4a` URL. Falls back to encoding the raw file when denoise fails.
    public static func finalize(rawCAF: URL) async throws -> URL {
        try await finalizeWithReport(rawCAF: rawCAF).url
    }

    public static func finalizeWithReport(rawCAF: URL) async throws -> (url: URL, report: Report) {
        let samples = try readFloatMono(url: rawCAF)
        guard !samples.samples.isEmpty else { throw TakeFinalizerError.empty }

        var processed: [Float]
        let rate: Double
        var usedDenoise = false
        var delay: TimeInterval = 0
        if let denoised = try? denoise(samples: samples.samples, sampleRate: samples.sampleRate),
           audible(denoised.samples, comparedTo: samples.samples) {
            delay = DelayEstimator.delaySeconds(
                reference: samples.samples,
                delayed: denoised.samples,
                sampleRate: denoised.sampleRate
            )
            processed = trimLeading(denoised.samples, delaySeconds: delay, sampleRate: denoised.sampleRate)
            rate = denoised.sampleRate
            usedDenoise = true
        } else {
            processed = samples.samples
            rate = samples.sampleRate
        }

        // `.measurement` mic mode has no automatic gain, so phone takes are often very quiet.
        let gain = LoudnessNormalizer.gain(for: processed)
        LoudnessNormalizer.apply(gain: gain, to: &processed)

        let resampled = resample(processed, from: rate, to: outputSampleRate)
        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("take-final-\(UUID().uuidString).m4a")
        try writeAAC(samples: resampled, sampleRate: outputSampleRate, to: outURL)
        try? FileManager.default.removeItem(at: rawCAF)
        let report = Report(
            inputPeak: peak(samples.samples),
            usedDenoise: usedDenoise,
            denoiseDelaySeconds: delay,
            gain: gain,
            outputPeak: peak(resampled)
        )
        return (outURL, report)
    }

    // MARK: - Read / write

    private static func readFloatMono(url: URL) throws -> (samples: [Float], sampleRate: Double) {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let frameCount = AVAudioFrameCount(file.length)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw TakeFinalizerError.empty
        }
        try file.read(into: buffer)
        let channel = buffer.floatChannelData?[0]
        let count = Int(buffer.frameLength)
        var samples = [Float](repeating: 0, count: count)
        if let channel {
            for i in 0..<count { samples[i] = channel[i] }
        }
        // Mix down if multi-channel.
        if format.channelCount > 1, let channels = buffer.floatChannelData {
            for i in 0..<count {
                var sum: Float = 0
                for c in 0..<Int(format.channelCount) {
                    sum += channels[c][i]
                }
                samples[i] = sum / Float(format.channelCount)
            }
        }
        return (samples, format.sampleRate)
    }

    private static func writeAAC(samples: [Float], sampleRate: Double, to url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: bitRate,
        ]
        let floatFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        )
        guard let floatFormat else { throw TakeFinalizerError.encodeFailed }
        // `commonFormat` locks the file's processing format to the PCM we write.
        // A settings-only AAC file often expects a different layout and encodes silence.
        let file = try AVAudioFile(
            forWriting: url,
            settings: settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        let writeFormat = file.processingFormat
        let writeSamples: [Float]
        if abs(writeFormat.sampleRate - sampleRate) > 0.5 || writeFormat.channelCount != 1 {
            writeSamples = resample(samples, from: sampleRate, to: writeFormat.sampleRate)
        } else {
            writeSamples = samples
        }
        let frameCount = AVAudioFrameCount(writeSamples.count)
        let bufferFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: writeFormat.sampleRate,
            channels: 1,
            interleaved: false
        ) ?? floatFormat
        guard let buffer = AVAudioPCMBuffer(pcmFormat: bufferFormat, frameCapacity: frameCount) else {
            throw TakeFinalizerError.encodeFailed
        }
        buffer.frameLength = frameCount
        writeSamples.withUnsafeBufferPointer { src in
            buffer.floatChannelData?[0].update(from: src.baseAddress!, count: writeSamples.count)
        }
        try file.write(from: buffer)
    }

    /// Denoise that comes back as silence must not replace the take.
    private static func audible(_ candidate: [Float], comparedTo original: [Float]) -> Bool {
        let originalPeak = peak(original)
        guard originalPeak > 0.01 else { return peak(candidate) > 0 }
        return peak(candidate) > originalPeak * 0.02
    }

    private static func peak(_ samples: [Float]) -> Float {
        var maxAmp: Float = 0
        for sample in samples {
            maxAmp = max(maxAmp, abs(sample))
        }
        return maxAmp
    }

    // MARK: - Denoise

    private static func denoise(samples: [Float], sampleRate: Double) throws -> (samples: [Float], sampleRate: Double) {
        #if targetEnvironment(simulator)
        // Isolation unit is uneven on Simulator — fall through to encode path.
        throw TakeFinalizerError.encodeFailed
        #else
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)

        let isolation = AVAudioUnitEffect(audioComponentDescription: AudioComponentDescription(
            componentType: kAudioUnitType_Effect,
            componentSubType: kAudioUnitSubType_AUSoundIsolation,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        ))
        engine.attach(isolation)
        // HighQualityVoice = 0 on iOS 18+.
        isolation.auAudioUnit.parameterTree?.parameter(withAddress: 1)?.value = 0

        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        )
        guard let format else { throw TakeFinalizerError.encodeFailed }

        // Manual rendering reads the mixer output. Muting it writes a silent file.
        // Enable offline mode before connecting, or the graph stays on the hardware output.
        try engine.enableManualRenderingMode(
            .offline,
            format: format,
            maximumFrameCount: 4096
        )
        engine.connect(player, to: isolation, format: format)
        engine.connect(isolation, to: engine.mainMixerNode, format: format)

        let frameCount = AVAudioFrameCount(samples.count)
        // Extra silence so the unit can flush its delay line.
        let padFrames = AVAudioFrameCount(sampleRate * 0.2)
        guard let inBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw TakeFinalizerError.encodeFailed
        }
        inBuffer.frameLength = frameCount
        samples.withUnsafeBufferPointer { src in
            inBuffer.floatChannelData?[0].update(from: src.baseAddress!, count: samples.count)
        }

        try engine.start()
        player.scheduleBuffer(inBuffer, completionHandler: nil)
        if let silence = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: padFrames) {
            silence.frameLength = padFrames
            player.scheduleBuffer(silence, completionHandler: nil)
        }
        player.play()

        var output = [Float]()
        output.reserveCapacity(samples.count + Int(padFrames))
        guard let renderBuffer = AVAudioPCMBuffer(
            pcmFormat: engine.manualRenderingFormat,
            frameCapacity: engine.manualRenderingMaximumFrameCount
        ) else {
            throw TakeFinalizerError.encodeFailed
        }

        while engine.manualRenderingSampleTime < Int64(frameCount + padFrames) {
            let framesToRender = min(
                engine.manualRenderingMaximumFrameCount,
                AVAudioFrameCount(Int64(frameCount + padFrames) - engine.manualRenderingSampleTime)
            )
            let status = try engine.renderOffline(framesToRender, to: renderBuffer)
            if status == .success, let channel = renderBuffer.floatChannelData?[0] {
                let n = Int(renderBuffer.frameLength)
                output.append(contentsOf: UnsafeBufferPointer(start: channel, count: n))
            } else if status == .error {
                throw TakeFinalizerError.encodeFailed
            }
        }

        engine.stop()
        // Keep input length; delay trim happens separately.
        if output.count > samples.count {
            output = Array(output.prefix(samples.count))
        }
        return (output, sampleRate)
        #endif
    }

    private static func trimLeading(_ samples: [Float], delaySeconds: TimeInterval, sampleRate: Double) -> [Float] {
        let skip = max(0, Int(delaySeconds * sampleRate))
        guard skip < samples.count else { return samples }
        return Array(samples.dropFirst(skip))
    }

    private static func resample(_ samples: [Float], from: Double, to: Double) -> [Float] {
        guard from > 0, to > 0, abs(from - to) > 0.5 else { return samples }
        let ratio = to / from
        let outCount = max(1, Int((Double(samples.count) * ratio).rounded()))
        var out = [Float](repeating: 0, count: outCount)
        for i in 0..<outCount {
            let src = Double(i) / ratio
            let i0 = Int(src)
            let i1 = min(samples.count - 1, i0 + 1)
            let frac = Float(src - Double(i0))
            let s0 = samples[min(i0, samples.count - 1)]
            let s1 = samples[i1]
            out[i] = s0 + (s1 - s0) * frac
        }
        return out
    }
}
