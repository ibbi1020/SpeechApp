import AVFoundation
import Foundation

/// Writes mic chunks to a temp CAF while the take clock is running.
@MainActor
public final class TakeRecorder {
    public private(set) var fileURL: URL?
    private var audioFile: AVAudioFile?
    private var writing = false
    private let directory: URL

    public init(directory: URL = FileManager.default.temporaryDirectory) {
        self.directory = directory
    }

    public func start() throws {
        _ = stop()
        let url = directory.appendingPathComponent("take-\(UUID().uuidString).caf")
        fileURL = url
        writing = true
    }

    public func setWriting(_ on: Bool) {
        writing = on
    }

    public func append(_ chunk: AudioChunk) {
        guard writing, let fileURL else { return }
        guard !chunk.samples.isEmpty, chunk.sampleRate > 0 else { return }
        do {
            let format = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: chunk.sampleRate,
                channels: 1,
                interleaved: false
            )
            guard let format else { return }
            if audioFile == nil {
                audioFile = try AVAudioFile(
                    forWriting: fileURL,
                    settings: format.settings,
                    commonFormat: .pcmFormatFloat32,
                    interleaved: false
                )
            }
            guard let audioFile else { return }
            let frameCount = AVAudioFrameCount(chunk.samples.count)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
            buffer.frameLength = frameCount
            chunk.samples.withUnsafeBufferPointer { src in
                if let dest = buffer.floatChannelData?[0] {
                    dest.update(from: src.baseAddress!, count: chunk.samples.count)
                }
            }
            try audioFile.write(from: buffer)
        } catch {
            // Leave the partial file; finalizer will fall back or fail visibly.
        }
    }

    @discardableResult
    public func stop() -> URL? {
        writing = false
        audioFile = nil
        let url = fileURL
        fileURL = nil
        return url
    }
}
