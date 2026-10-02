import Foundation

/// One `transcript.partial` from Grok streaming STT.
public struct GrokPartialEvent: Equatable, Sendable {
    public let text: String
    public let isFinal: Bool
    public let speechFinal: Bool
    public let words: [GrokTimedWord]

    public init(text: String, isFinal: Bool, speechFinal: Bool, words: [GrokTimedWord] = []) {
        self.text = text
        self.isFinal = isFinal
        self.speechFinal = speechFinal
        self.words = words
    }
}

public struct GrokTimedWord: Equatable, Sendable {
    public let text: String
    public let start: TimeInterval
    public let end: TimeInterval

    public init(text: String, start: TimeInterval, end: TimeInterval) {
        self.text = text
        self.start = start
        self.end = end
    }
}

/// Stitches interim, chunk-final, and utterance-final events into aligner tokens.
///
/// `speech_final` text is the whole utterance. If that text drops earlier chunk
/// finals, those words are kept and the new text is appended.
public struct GrokTranscriptStitcher: Sendable {
    public private(set) var committed = ""
    public private(set) var locked = ""
    public private(set) var live = ""

    public init() {}

    /// Word times are sometimes counted from the chunk, while `segmentStart` is counted from the stream.
    /// Leave times alone when they are already on the stream clock.
    public static func absoluteWords(
        _ words: [GrokTimedWord],
        segmentStart: TimeInterval
    ) -> [GrokTimedWord] {
        guard let first = words.first, segmentStart > first.start + 0.05 else { return words }
        return words.map {
            GrokTimedWord(text: $0.text, start: $0.start + segmentStart, end: $0.end + segmentStart)
        }
    }

    public var rawText: String {
        Self.join([committed, locked, live])
    }

    public mutating func apply(_ event: GrokPartialEvent) -> TranscriptionUpdate? {
        let incoming = Self.words(in: event.text)
        guard !incoming.isEmpty || event.speechFinal else { return nil }

        let finalTokens: [SpokenToken]
        if event.speechFinal {
            let lockedWords = Self.words(in: locked)
            let stitched: String
            let fresh: [String]
            if lockedWords.isEmpty || Self.hasPrefix(incoming, prefix: lockedWords) {
                stitched = event.text
                fresh = Array(incoming.dropFirst(lockedWords.count))
            } else {
                stitched = Self.join([locked, event.text])
                fresh = incoming
            }
            committed = Self.join([committed, stitched])
            locked = ""
            live = ""
            finalTokens = Self.tokens(
                surfaces: fresh,
                timed: event.words,
                timedSurfaces: incoming,
                isFinal: true
            )
        } else if event.isFinal {
            locked = Self.join([locked, event.text])
            live = ""
            finalTokens = Self.tokens(
                surfaces: incoming,
                timed: event.words,
                timedSurfaces: incoming,
                isFinal: true
            )
        } else {
            live = event.text
            finalTokens = []
        }

        let volatileTokens: [SpokenToken]
        if live.isEmpty {
            volatileTokens = []
        } else {
            let liveWords = Self.words(in: live)
            volatileTokens = Self.tokens(
                surfaces: liveWords,
                timed: event.words,
                timedSurfaces: liveWords,
                isFinal: false
            )
        }

        let tokens = finalTokens + volatileTokens
        guard !tokens.isEmpty || !rawText.isEmpty else { return nil }
        return TranscriptionUpdate(
            tokens: tokens,
            engineKind: .grokVoiceTranscribe,
            rawText: rawText
        )
    }

    static func words(in text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map(String.init).filter { !$0.isEmpty }
    }

    private static func hasPrefix(_ words: [String], prefix: [String]) -> Bool {
        guard words.count >= prefix.count else { return false }
        return Array(words.prefix(prefix.count)) == prefix
    }

    private static func join(_ parts: [String]) -> String {
        parts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func tokens(
        surfaces: [String],
        timed: [GrokTimedWord],
        timedSurfaces: [String],
        isFinal: Bool
    ) -> [SpokenToken] {
        let times = alignedTimes(surfaces: surfaces, timed: timed, timedSurfaces: timedSurfaces)
        return surfaces.enumerated().map { index, surface in
            let time = index < times.count ? times[index] : nil
            return SpokenToken(
                surface: surface,
                startTime: time?.start,
                endTime: time?.end,
                isFinal: isFinal
            )
        }
    }

    /// Use word times when they line up with the surfaces we are emitting.
    private static func alignedTimes(
        surfaces: [String],
        timed: [GrokTimedWord],
        timedSurfaces: [String]
    ) -> [GrokTimedWord?] {
        guard !surfaces.isEmpty else { return [] }
        if timed.count == timedSurfaces.count, timedSurfaces.count >= surfaces.count {
            let start = timedSurfaces.count - surfaces.count
            return (0..<surfaces.count).map { timed[start + $0] }
        }
        if timed.count == surfaces.count {
            return timed.map { Optional($0) }
        }
        return Array(repeating: nil, count: surfaces.count)
    }
}
