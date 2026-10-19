import AVFoundation
import SpeechAppKit

/// Reads a bundled bed and converts it to the conversation playback format.
enum AmbientFileBuffer {
    static func make(url: URL, target: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let sourceFormat = file.processingFormat
        let frames = AVAudioFrameCount(file.length)
        guard frames > 0,
              let source = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: frames)
        else { return nil }
        do {
            try file.read(into: source)
        } catch {
            return nil
        }
        source.frameLength = frames
        if source.format.commonFormat == target.commonFormat,
           source.format.sampleRate == target.sampleRate,
           source.format.channelCount == target.channelCount {
            return source
        }
        guard let converter = AVAudioConverter(from: sourceFormat, to: target) else { return nil }
        let ratio = target.sampleRate / sourceFormat.sampleRate
        let capacity = AVAudioFrameCount(ceil(Double(source.frameLength) * ratio)) + 64
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return nil }
        var error: NSError?
        var provided = false
        let status = converter.convert(to: output, error: &error) { _, statusOut in
            if provided {
                statusOut.pointee = .endOfStream
                return nil
            }
            provided = true
            statusOut.pointee = .haveData
            return source
        }
        guard error == nil, status != .error, output.frameLength > 0 else { return nil }
        return output
    }
}
