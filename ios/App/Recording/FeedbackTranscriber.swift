import Foundation
import OSLog
import SpeechAppKit

/// A Grok speech-to-text stream used only for listen-back feedback.
///
/// It gets no hint words: Reading's live stream sends the passage as hints, and with
/// them Grok writes the passage word even when another was said ("ship" for "sheep").
/// Feed it exactly the audio the take recorder writes, so word times line up with the file.
@MainActor
final class FeedbackTranscriber {
    private static let log = Logger(subsystem: "com.speechapp", category: "FeedbackTranscriber")

    private let engine: GrokTranscriptionEngine
    private var collector: Task<[RecordedWord], Never>?
    private(set) var failed = false

    init(relayBase: URL, bearerToken: String) {
        engine = GrokTranscriptionEngine(relayBase: relayBase, bearerToken: bearerToken)
    }

    func start() async {
        // Subscribe before prepare, or early words are lost.
        let updates = engine.updates
        collector = Task {
            var words: [RecordedWord] = []
            for await update in updates {
                for token in update.tokens where token.isFinal {
                    guard let start = token.startTime, let end = token.endTime else { continue }
                    words.append(RecordedWord(surface: token.surface, start: start, end: end))
                }
            }
            return words
        }
        do {
            try await engine.prepareIfNeeded(locale: Locale(identifier: "en-US"))
            try await engine.start(locale: Locale(identifier: "en-US"), preference: .autoPreferSpeechTranscriber)
        } catch {
            failed = true
            Self.log.error("feedback stream failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func append(_ chunk: AudioChunk) {
        guard !failed else { return }
        engine.append(chunk)
    }

    /// Sends the end of audio, waits for the last words, and returns every timed word.
    func finish() async -> [RecordedWord] {
        await engine.stop()
        return await collector?.value ?? []
    }
}
