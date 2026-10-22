import AVFoundation
import Foundation
import os

/// Writes mic chunks to a temp CAF while the take clock is running.
///
/// `append` returns immediately and is safe to call from the audio thread.
/// `stop` waits until those chunks are in the file.
public final class TakeRecorder: @unchecked Sendable {
    private let writer: Writer

    /// The open file, or nil once recording has stopped.
    public var fileURL: URL? { writer.fileURL }

    /// Seconds of audio written so far. This is the saved file's timeline.
    public var writtenSeconds: TimeInterval { writer.writtenSeconds }

    public init(directory: URL = FileManager.default.temporaryDirectory) {
        writer = Writer(directory: directory)
    }

    public func start() throws {
        writer.start()
    }

    public func setWriting(_ on: Bool) {
        writer.setWriting(on)
    }

    public func append(_ chunk: AudioChunk) {
        writer.append(chunk)
    }

    @discardableResult
    public func stop() -> URL? {
        writer.stop()
    }
}

/// File writes stay on one queue. The audio thread only hands chunks over.
private final class Writer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "speechapp.take-recorder")
    private let seconds = OSAllocatedUnfairLock(initialState: TimeInterval(0))
    private let urlBox = OSAllocatedUnfairLock<URL?>(initialState: nil)
    private let directory: URL
    private var audioFile: AVAudioFile?
    private var writing = false
    private var openURL: URL?

    init(directory: URL) {
        self.directory = directory
    }

    var fileURL: URL? { urlBox.withLock { $0 } }

    var writtenSeconds: TimeInterval { seconds.withLock { $0 } }

    func start() {
        queue.sync {
            closeFile()
            let url = directory.appendingPathComponent("take-\(UUID().uuidString).caf")
            openURL = url
            urlBox.withLock { $0 = url }
            seconds.withLock { $0 = 0 }
            writing = true
            audioFile = nil
        }
    }

    func setWriting(_ on: Bool) {
        queue.sync { writing = on }
    }

    func append(_ chunk: AudioChunk) {
        queue.async {
            self.write(chunk)
        }
    }

    func stop() -> URL? {
        queue.sync {
            writing = false
            closeFile()
            let url = openURL
            openURL = nil
            urlBox.withLock { $0 = nil }
            return url
        }
    }

    private func write(_ chunk: AudioChunk) {
        guard writing, let openURL else { return }
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
                    forWriting: openURL,
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
            let added = Double(chunk.samples.count) / chunk.sampleRate
            seconds.withLock { $0 += added }
        } catch {
            // Leave the partial file; finalizer will fall back or fail visibly.
        }
    }

    private func closeFile() {
        audioFile = nil
    }
}
