#if os(macOS)
import Foundation
import SpeechAppKit

/// Turns clips.json scripts into WAV files with exact labels, using the Mac `say` voice.
/// Each stretch of speech is rendered on its own, trimmed, and placed on the timeline,
/// so every planted silence and labeled span has a known start and end.
enum GenerateCommand {
    static let sampleRate: Double = 16_000
    /// Breath between two separately rendered stretches of speech.
    static let joinGap: TimeInterval = 0.12

    static func run(_ options: Options) throws {
        let specs = try JSONDecoder().decode(
            [ClipSpec].self,
            from: Data(contentsOf: URL(fileURLWithPath: options.specs))
        )
        let outDir = URL(fileURLWithPath: options.dir).appendingPathComponent("generated")
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        for spec in specs {
            if let only = options.only, !spec.name.contains(only) { continue }
            let script = try FeedbackScript(spec.script)
            var rendered: [(samples: [Float], wordCount: Int)] = []
            var failure: Error?
            let layout = script.layout(gapBetweenSpeech: joinGap) { words in
                do {
                    let samples = try speak(words.joined(separator: " "), voice: spec.voice, rate: spec.rate)
                    rendered.append((samples, words.count))
                    let length = Double(samples.count) / sampleRate
                    return (Array(repeating: (0, length), count: words.count), length)
                } catch {
                    failure = error
                    return ([], 0)
                }
            }
            if let failure { throw failure }

            var timeline = [Float](repeating: 0, count: Int((layout.duration + 0.5) * sampleRate))
            var wordIndex = 0
            for piece in rendered {
                let start = Int(layout.words[wordIndex].start * sampleRate)
                for (offset, sample) in piece.samples.enumerated() where start + offset < timeline.count {
                    timeline[start + offset] = sample
                }
                wordIndex += piece.wordCount
            }

            let audioURL = outDir.appendingPathComponent("\(spec.name).wav")
            try AudioIO.writeWAV(timeline, sampleRate: sampleRate, to: audioURL)
            let labels = ClipLabels(
                why: spec.why,
                script: spec.script,
                exercise: spec.exercise,
                passage: spec.passage,
                partnerTurns: layout.partnerTurns.isEmpty ? nil : layout.partnerTurns,
                labels: layout.labels
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(labels).write(to: Clip(audio: audioURL).labelsURL)
            print("generated \(spec.name)  \(String(format: "%.1f", Double(timeline.count) / sampleRate)) s  \(layout.labels.count) labels")
        }
    }

    /// Renders text with `say` at 16 kHz and trims the silence the voice adds at each end.
    static func speak(_ text: String, voice: String?, rate: Int?) throws -> [Float] {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("feedback-say-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: tmp) }
        var args = ["-o", tmp.path, "--file-format=WAVE", "--data-format=LEF32@16000"]
        if let voice { args += ["-v", voice] }
        if let rate { args += ["-r", String(rate)] }
        args.append(text)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        process.arguments = args
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw CLIError.failed("say failed for “\(text)”")
        }
        let audio = try AudioIO.read(tmp)
        return trim(audio.samples)
    }

    static func trim(_ samples: [Float], threshold: Float = 0.01) -> [Float] {
        guard let first = samples.firstIndex(where: { abs($0) > threshold }),
              let last = samples.lastIndex(where: { abs($0) > threshold })
        else { return [] }
        return Array(samples[first...last])
    }
}
#endif
