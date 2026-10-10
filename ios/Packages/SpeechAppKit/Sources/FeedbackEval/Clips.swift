#if os(macOS)
import AVFoundation
import Foundation
import SpeechAppKit

/// One clip spec in eval/feedback/clips.json.
struct ClipSpec: Codable {
    let name: String
    let why: String
    let script: String
    let voice: String?
    /// Words per minute for `say`. Leave empty for the voice default.
    let rate: Int?
}

/// `<clip>.labels.json`: what a person (or the generator) says should be flagged.
struct ClipLabels: Codable {
    var why: String?
    var script: String?
    var labels: [FeedbackLabel]
}

/// `<clip>.grok.json`: cached Grok words so rules can be re-scored for free.
struct GrokCache: Codable {
    struct Word: Codable {
        let surface: String
        let start: TimeInterval
        let end: TimeInterval
    }

    let rawText: String
    let words: [Word]
    let audioSeconds: TimeInterval
    let transcribedAt: Date

    var recordedWords: [RecordedWord] {
        words.map { RecordedWord(surface: $0.surface, start: $0.start, end: $0.end) }
    }
}

/// A clip on disk and its side files.
struct Clip {
    let audio: URL

    var name: String { audio.deletingPathExtension().lastPathComponent }
    private var base: URL { audio.deletingPathExtension() }
    var labelsURL: URL { base.appendingPathExtension("labels.json") }
    var audacityURL: URL { base.appendingPathExtension("txt") }
    var grokURL: URL { base.appendingPathExtension("grok.json") }

    static let audioExtensions: Set<String> = ["wav", "m4a", "caf", "aiff", "mp3"]

    static func all(in dir: String, only: String?) -> [Clip] {
        let root = URL(fileURLWithPath: dir)
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else {
            return []
        }
        var clips: [Clip] = []
        for case let url as URL in walker where audioExtensions.contains(url.pathExtension.lowercased()) {
            let clip = Clip(audio: url)
            if let only, !clip.name.contains(only) { continue }
            clips.append(clip)
        }
        return clips.sorted { $0.audio.path < $1.audio.path }
    }

    /// Labels from `<clip>.labels.json`, or an Audacity export `<clip>.txt`.
    func labels() throws -> ClipLabels? {
        if FileManager.default.fileExists(atPath: labelsURL.path) {
            return try JSONDecoder().decode(ClipLabels.self, from: Data(contentsOf: labelsURL))
        }
        if FileManager.default.fileExists(atPath: audacityURL.path) {
            let text = try String(contentsOf: audacityURL, encoding: .utf8)
            return ClipLabels(why: nil, script: nil, labels: FeedbackLabel.parseAudacity(text))
        }
        return nil
    }

    func grok() -> GrokCache? {
        guard let data = try? Data(contentsOf: grokURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(GrokCache.self, from: data)
    }
}

enum AudioIO {
    /// Mono float samples, first channel.
    static func read(_ url: URL) throws -> (samples: [Float], sampleRate: Double) {
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        let format = file.processingFormat
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length)) else {
            throw CLIError.failed("Could not read \(url.lastPathComponent)")
        }
        try file.read(into: buffer)
        let count = Int(buffer.frameLength)
        let samples = buffer.floatChannelData.map { Array(UnsafeBufferPointer(start: $0[0], count: count)) } ?? []
        return (samples, format.sampleRate)
    }

    /// 16-bit PCM WAV, mono.
    static func writeWAV(_ samples: [Float], sampleRate: Double, to url: URL) throws {
        try? FileManager.default.removeItem(at: url)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        let file = try AVAudioFile(
            forWriting: url,
            settings: settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ), let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))
        else {
            throw CLIError.failed("Could not write \(url.lastPathComponent)")
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { src in
            buffer.floatChannelData?[0].update(from: src.baseAddress!, count: samples.count)
        }
        try file.write(from: buffer)
    }
}
#endif
