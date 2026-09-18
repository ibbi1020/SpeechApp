import AVFoundation
import Foundation

public struct AudioChunk: Sendable {
    public let samples: [Float]
    public let sampleRate: Double
    public let hostTime: TimeInterval

    public init(samples: [Float], sampleRate: Double, hostTime: TimeInterval) {
        self.samples = samples
        self.sampleRate = sampleRate
        self.hostTime = hostTime
    }
}

public protocol AudioSource: AnyObject, Sendable {
    var chunks: AsyncStream<AudioChunk> { get }
    func start() async throws
    func stop() async
}

/// Replays a WAV/CAF file as real-time PCM chunks for deterministic tests and demos.
public final class FileReplayAudioSource: AudioSource, @unchecked Sendable {
    public let chunks: AsyncStream<AudioChunk>
    private let continuation: AsyncStream<AudioChunk>.Continuation
    private let fileURL: URL
    private let chunkDuration: TimeInterval
    private var task: Task<Void, Never>?

    public init(fileURL: URL, chunkDuration: TimeInterval = 0.05) {
        self.fileURL = fileURL
        self.chunkDuration = chunkDuration
        let pair = AsyncStream<AudioChunk>.makeStream(bufferingPolicy: .bufferingNewest(32))
        self.chunks = pair.stream
        self.continuation = pair.continuation
    }

    public func start() async throws {
        let file = try AVAudioFile(forReading: fileURL)
        let format = file.processingFormat
        let framesPerChunk = AVAudioFrameCount(max(1, format.sampleRate * chunkDuration))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: framesPerChunk) else {
            throw AudioSourceError.bufferAllocationFailed
        }

        task = Task { [continuation, chunkDuration] in
            var hostTime: TimeInterval = 0
            while file.framePosition < file.length && !Task.isCancelled {
                do {
                    try file.read(into: buffer)
                } catch {
                    break
                }
                guard buffer.frameLength > 0 else { break }
                let samples = Self.floatSamples(from: buffer)
                continuation.yield(
                    AudioChunk(
                        samples: samples,
                        sampleRate: format.sampleRate,
                        hostTime: hostTime
                    )
                )
                hostTime += chunkDuration
                try? await Task.sleep(nanoseconds: UInt64(chunkDuration * 1_000_000_000))
            }
            continuation.finish()
        }
    }

    public func stop() async {
        task?.cancel()
        task = nil
        continuation.finish()
    }

    public static func floatSamples(from buffer: AVAudioPCMBuffer) -> [Float] {
        let count = Int(buffer.frameLength)
        if let channel = buffer.floatChannelData?[0] {
            return Array(UnsafeBufferPointer(start: channel, count: count))
        }
        if let channel = buffer.int16ChannelData?[0] {
            return (0..<count).map { Float(channel[$0]) / Float(Int16.max) }
        }
        return []
    }
}

public enum AudioSourceError: Error, Sendable {
    case bufferAllocationFailed
    case engineStartFailed
    case permissionDenied
}

#if os(iOS)
/// Live microphone via AVAudioEngine tap.
public final class MicAudioSource: AudioSource, @unchecked Sendable {
    public let chunks: AsyncStream<AudioChunk>
    private let continuation: AsyncStream<AudioChunk>.Continuation
    private let engine = AVAudioEngine()
    private var startHost: TimeInterval = 0

    public init() {
        let pair = AsyncStream<AudioChunk>.makeStream(bufferingPolicy: .bufferingNewest(32))
        self.chunks = pair.stream
        self.continuation = pair.continuation
    }

    public func start() async throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
        try session.setActive(true)

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        startHost = ProcessInfo.processInfo.systemUptime

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [continuation, startHost] buffer, _ in
            let samples = FileReplayAudioSource.floatSamples(from: buffer)
            let host = ProcessInfo.processInfo.systemUptime - startHost
            continuation.yield(
                AudioChunk(
                    samples: samples,
                    sampleRate: format.sampleRate,
                    hostTime: host
                )
            )
        }

        engine.prepare()
        try engine.start()
    }

    public func stop() async {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        continuation.finish()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
#endif
