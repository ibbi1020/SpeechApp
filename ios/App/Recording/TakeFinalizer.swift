import AVFoundation
import Foundation
import SpeechAppKit

enum TakeFinalizerError: Error {
    case empty
    case encodeFailed
}

/// Denoise (AUSoundIsolation) → delay fix → AAC 16 kHz mono 32 kbps.
enum TakeFinalizer {
    static let outputSampleRate: Double = 16_000
    static let bitRate = 32_000

    /// Returns a local `.m4a` URL. Falls back to encoding the raw file when denoise fails.
    static func finalize(rawCAF: URL) async throws -> URL {
        let samples = try readFloatMono(url: rawCAF)
        guard !samples.samples.isEmpty else { throw TakeFinalizerError.empty }

        let processed: [Float]
        let rate: Double
        if let denoised = try? denoise(samples: samples.samples, sampleRate: samples.sampleRate) {
            let delay = DelayEstimator.delaySeconds(
                reference: samples.samples,
                delayed: denoised.samples,
                sampleRate: denoised.sampleRate
            )
            processed = trimLeading(denoised.samples, delaySeconds: delay, sampleRate: denoised.sampleRate)
            rate = denoised.sampleRate
        } else {
            processed = samples.samples
            rate = samples.sampleRate
        }

        let resampled = resample(processed, from: rate, to: outputSampleRate)
        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("take-final-\(UUID().uuidString).m4a")
        try writeAAC(samples: resampled, sampleRate: outputSampleRate, to: outURL)
        try? FileManager.default.removeItem(at: rawCAF)
        return outURL
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
        let file = try AVAudioFile(forWriting: url, settings: settings)
        let frameCount = AVAudioFrameCount(samples.count)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: floatFormat, frameCapacity: frameCount) else {
            throw TakeFinalizerError.encodeFailed
        }
        buffer.frameLength = frameCount
        samples.withUnsafeBufferPointer { src in
            buffer.floatChannelData?[0].update(from: src.baseAddress!, count: samples.count)
        }
        try file.write(from: buffer)
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

        engine.connect(player, to: isolation, format: format)
        engine.connect(isolation, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 0

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

        try engine.enableManualRenderingMode(
            .offline,
            format: format,
            maximumFrameCount: 4096
        )
        try engine.start()
        player.scheduleBuffer(inBuffer, completionHandler: nil)
        if let silence = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: padFrames) {
            silence.frameLength = padFrames
            player.scheduleBuffer(silence, completionHandler: nil)
        }
        player.play()

        var output = [Float]()
        output.reserveCapacity(samples.count + Int(padFrames))
        let outBuffer = engine.manualRenderingBufferFormat
        guard let renderBuffer = AVAudioPCMBuffer(
            pcmFormat: outBuffer,
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
