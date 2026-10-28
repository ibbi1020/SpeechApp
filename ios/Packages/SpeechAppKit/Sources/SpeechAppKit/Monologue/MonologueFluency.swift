import Foundation

/// Utterance fluency for one monologue take, measured on this take's words.
///
/// A breakdown pause is a real silence of at least 250 ms between words.
/// Grok word edges sit about 0.2 s inside the sound, so that padding comes off
/// the gap before the 250 ms test. Syllables are vowel-letter groups.
/// The screen shows each number on its own. There is no combined fluency score.
public enum MonologueFluency {
    public static let minimumPause: TimeInterval = 0.25

    public struct Profile: Equatable, Sendable {
        /// Syllables per minute of the take clock, pauses included.
        public var speechRate: Double?
        /// Content syllables per minute of phonation. Fillers are left out.
        public var articulationRate: Double?
        /// Speech rate after fillers and abandoned restarts are left out.
        public var trimmedSpeechRate: Double?
        /// Mean syllables between breakdown pauses.
        public var meanLengthOfRun: Double?
        public var phonationTimeRatio: Double?
        /// Breakdown pauses per minute of the take clock.
        public var pauseFrequency: Double?
        public var meanPause: TimeInterval?
        /// Filled pauses per minute of phonation, including a single "um".
        public var filledPauseFrequency: Double?
        public var pauseCount: Int
        public var pauseTime: TimeInterval
    }

    public enum Label {
        public static let speechRate = "Speech rate"
        public static let articulationRate = "Articulation rate"
        public static let meanLengthOfRun = "Mean length of run"
        public static let trimmedSpeechRate = "Trimmed speech rate"
        public static let phonationTimeRatio = "Phonation-time ratio"
        public static let pauseFrequency = "Pause frequency"
        public static let meanPause = "Mean pause"
        public static let filledPauses = "Filled pauses"
        public static let speakingTime = "Speaking time"

        public static func verbatimReuse(versus take: Int) -> String {
            "Verbatim reuse vs take \(take)"
        }
    }

    public static func measure(_ take: MonologueTake) -> Profile {
        let words = take.words.sorted { $0.start < $1.start }
        let wall = take.wallSeconds
        let spoken = spokenSeconds(take, words: words)
        let pauseLengths = pauseLengths(take, words: words)
        let pauseCount = pauseLengths.count
        let pauseTime = pauseLengths.reduce(0, +)
        let minutes = wall / 60

        let raw = syllables(take, words: words, dropFillers: false, dropAbandoned: false)
        let content = syllables(take, words: words, dropFillers: true, dropAbandoned: false)
        let trimmed = syllables(take, words: words, dropFillers: true, dropAbandoned: true)
        let fillers = fillerCount(take, words: words)

        return Profile(
            speechRate: perMinute(raw, minutes: minutes),
            articulationRate: perMinute(content, minutes: spoken / 60),
            trimmedSpeechRate: perMinute(trimmed, minutes: minutes),
            meanLengthOfRun: meanRun(take, words: words, pauseCount: pauseCount),
            phonationTimeRatio: MonologuePhonation.ratio(spoken: spoken, wall: wall),
            pauseFrequency: minutes > 0 ? Double(pauseCount) / minutes : nil,
            meanPause: pauseCount > 0 ? pauseTime / Double(pauseCount) : nil,
            filledPauseFrequency: spoken > 0 ? Double(fillers) * 60 / spoken : nil,
            pauseCount: pauseCount,
            pauseTime: pauseTime
        )
    }

    // MARK: - Pauses

    /// Real silence between two edges, once Grok's edge padding is removed.
    static func realSilence(from end: TimeInterval, to start: TimeInterval) -> TimeInterval? {
        let real = (start - end) - ReviewMarkers.wordEdgePadding
        guard real >= minimumPause - 0.001 else { return nil }
        return real
    }

    private static func pauseLengths(_ take: MonologueTake, words: [RecordedWord]) -> [TimeInterval] {
        let spans: [(TimeInterval, TimeInterval)]
        if words.isEmpty {
            spans = ConversationSpeechMetrics.merged(take.ranges).map { ($0.start, $0.end) }
        } else {
            spans = words.map { ($0.start, $0.end) }
        }
        guard spans.count >= 2 else { return [] }
        var lengths: [TimeInterval] = []
        for index in 1..<spans.count {
            if let silence = realSilence(from: spans[index - 1].1, to: spans[index].0) {
                lengths.append(silence)
            }
        }
        return lengths
    }

    // MARK: - Syllables

    private static func perMinute(_ syllables: Int, minutes: Double) -> Double? {
        guard minutes > 0, syllables > 0 else { return nil }
        return Double(syllables) / minutes
    }

    private static func spokenSeconds(_ take: MonologueTake, words: [RecordedWord]) -> TimeInterval {
        if take.spokenSeconds > 0 { return take.spokenSeconds }
        let spans = words.map { ConversationSpeechInterval(start: $0.start, end: $0.end) }
        return ConversationSpeechMetrics.unionDuration(spans)
    }

    private static func syllables(
        _ take: MonologueTake,
        words: [RecordedWord],
        dropFillers: Bool,
        dropAbandoned: Bool
    ) -> Int {
        if words.isEmpty {
            let text = dropFillers ? FillerWords.strippingTranscript(take.transcript) : take.transcript
            return ConversationPace.syllableCount(text)
        }
        let abandoned = dropAbandoned ? abandonedWordIDs(in: words) : []
        return words.reduce(0) { total, word in
            if dropFillers, word.isFiller { return total }
            if abandoned.contains(word.id) { return total }
            return total + ConversationPace.syllableCount(word.surface)
        }
    }

    /// The first copy of an exact restart. The second copy is the one they kept.
    private static func abandonedWordIDs(in words: [RecordedWord]) -> Set<UUID> {
        var dropped: Set<UUID> = []
        for restart in RestartDetector.find(in: words) {
            let copy = words.filter {
                !$0.isFiller && $0.start >= restart.start - 0.001 && $0.end <= restart.end + 0.001
            }
            for word in copy.prefix(restart.repeatedSurfaces.count) {
                dropped.insert(word.id)
            }
        }
        return dropped
    }

    private static func fillerCount(_ take: MonologueTake, words: [RecordedWord]) -> Int {
        if words.isEmpty {
            return take.transcript
                .split { $0.isWhitespace || $0.isNewline }
                .filter { FillerWords.isFiller(String($0)) }
                .count
        }
        return words.filter(\.isFiller).count
    }

    private static func meanRun(_ take: MonologueTake, words: [RecordedWord], pauseCount: Int) -> Double? {
        if words.isEmpty {
            let count = ConversationPace.syllableCount(FillerWords.strippingTranscript(take.transcript))
            guard count > 0 else { return nil }
            return Double(count) / Double(pauseCount + 1)
        }
        var runs: [[RecordedWord]] = []
        for word in words {
            if let previous = runs.last?.last,
               realSilence(from: previous.end, to: word.start) != nil
            {
                runs.append([word])
            } else if runs.isEmpty {
                runs.append([word])
            } else {
                runs[runs.count - 1].append(word)
            }
        }
        let lengths = runs.map { run in
            run.reduce(0) { $0 + ConversationPace.syllableCount($1.surface) }
        }.filter { $0 > 0 }
        guard !lengths.isEmpty else { return nil }
        return Double(lengths.reduce(0, +)) / Double(lengths.count)
    }
}
