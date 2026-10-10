#if os(macOS)
import Foundation
import SpeechAppKit

/// Streams each clip through the same Grok engine and relay the app uses,
/// and saves the final timed words next to the clip.
enum TranscribeCommand {
    static func run(_ options: Options) async throws {
        guard let relay = URL(string: options.relay) else { throw CLIError.usage("Bad --relay URL") }
        let clips = Clip.all(in: options.dir, only: options.only)
        if clips.isEmpty {
            print("No clips in \(options.dir). Run `generate` first, or add recordings to clips/real/.")
            return
        }
        for clip in clips {
            if !options.refresh, clip.grok() != nil {
                print("cached     \(clip.name)")
                continue
            }
            let cache = try await transcribe(clip, relay: relay, speed: options.speed)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(cache).write(to: clip.grokURL)
            print("transcribed \(clip.name)  “\(cache.rawText)”")
        }
    }

    static func transcribe(_ clip: Clip, relay: URL, speed: Double) async throws -> GrokCache {
        let audio = try AudioIO.read(clip.audio)
        let engine = GrokTranscriptionEngine(relayBase: relay, bearerToken: UUID().uuidString)
        // Subscribe before prepare, like the app, or early words are lost.
        let updates = engine.updates
        let collector = Task { () -> (words: [SpokenToken], text: String) in
            var finals: [SpokenToken] = []
            var text = ""
            for await update in updates {
                // Same rule as MonologueSessionView: keep timed final tokens from every update.
                finals.append(contentsOf: update.tokens.filter { $0.isFinal && $0.startTime != nil && $0.endTime != nil })
                let raw = update.rawText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !raw.isEmpty { text = raw }
            }
            return (finals, text)
        }

        do {
            try await engine.prepareIfNeeded(locale: Locale(identifier: "en-US"))
            try await engine.start(locale: Locale(identifier: "en-US"), preference: .autoPreferSpeechTranscriber)
        } catch {
            collector.cancel()
            throw CLIError.failed(
                "Could not reach Grok through \(relay.absoluteString). Start it with server/ensure-mint.sh (needs XAI_API_KEY in server/.env). \(error)"
            )
        }

        let chunkSeconds = 0.1
        let chunkSize = max(1, Int(audio.sampleRate * chunkSeconds))
        var offset = 0
        while offset < audio.samples.count {
            let end = min(audio.samples.count, offset + chunkSize)
            engine.append(AudioChunk(
                samples: Array(audio.samples[offset..<end]),
                sampleRate: audio.sampleRate,
                hostTime: Double(offset) / audio.sampleRate
            ))
            offset = end
            try await Task.sleep(for: .seconds(chunkSeconds / max(speed, 0.1)))
        }
        await engine.stop()
        let result = await collector.value

        return GrokCache(
            rawText: result.text,
            words: result.words.compactMap { token in
                guard let start = token.startTime, let end = token.endTime else { return nil }
                return GrokCache.Word(surface: token.surface, start: start, end: end)
            },
            audioSeconds: Double(audio.samples.count) / audio.sampleRate,
            transcribedAt: Date()
        )
    }
}
#endif
