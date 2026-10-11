import Foundation
import NaturalLanguage

/// Finds sustained stretches of non-English speech in a timed transcript.
///
/// Probe (2026-10-11): Grok streaming STT keeps foreign words in the transcript
/// (`Pero a veces…`) and puts a `language` field on each `transcript.partial`, but
/// mid-stream switches keep the first language tag. So detection is text-based:
/// non-Latin scripts count immediately; Latin-script windows ask
/// `NLLanguageRecognizer` how English they are. A single loanword or name is ignored.
public enum LanguageSpanDetector {
    /// Minimum consecutive non-English content words for a span.
    public static let minimumWordCount = 3
    /// Or this much sustained non-English speech (seconds).
    public static let minimumDuration: TimeInterval = 1.2
    /// A window scoring below this as English is treated as another language.
    ///
    /// Naming the language does not work. Grok writes Urdu and Hindi in Latin letters
    /// when the stream is English-dominant ("mujhe ghar par rehna pasand hai"), and
    /// `NLLanguageRecognizer` then guesses Italian, Swedish, or German at 0.25–0.70.
    /// What it is sure about is that the text is not English (P(en) ≤ 0.05), while
    /// learner English — mistakes and all — stays at 0.76 or above.
    public static let englishMaximum: Double = 0.5

    public struct Span: Equatable, Sendable {
        public let start: TimeInterval
        public let end: TimeInterval
        public let wordCount: Int

        public var duration: TimeInterval { max(0, end - start) }

        public init(start: TimeInterval, end: TimeInterval, wordCount: Int) {
            self.start = start
            self.end = end
            self.wordCount = wordCount
        }
    }

    /// Qualifying non-English spans inside `words` (already user-only, one answer).
    public static func spans(in words: [RecordedWord]) -> [Span] {
        let ordered = words.sorted { $0.start < $1.start }
        guard !ordered.isEmpty else { return [] }

        var flags = ordered.map { !$0.isFiller && hasNonLatinScript($0.surface) }
        markLatinWindows(ordered, flags: &flags)
        return qualifyingRuns(ordered, flags: flags)
    }

    /// True when this answer has at least one qualifying non-English span.
    public static func hasQualifyingSpan(in words: [RecordedWord]) -> Bool {
        !spans(in: words).isEmpty
    }

    // MARK: - Internals

    /// Sliding window of 3 content words for Latin-script languages.
    ///
    /// A window has to be backed up by the window next to it. One window on its own
    /// is as likely to be a loanword in an English sentence ("we cook daal") as a
    /// real switch, so a Latin-script slip needs four content words, not three.
    private static func markLatinWindows(_ ordered: [RecordedWord], flags: inout [Bool]) {
        let content = ordered.indices.filter { !ordered[$0].isFiller }
        guard content.count >= minimumWordCount else { return }
        let windows = (0...(content.count - minimumWordCount)).map { windowStart in
            content[windowStart..<(windowStart + minimumWordCount)]
        }
        let qualifies = windows.map { slice in
            slice.allSatisfy { flags[$0] }
                || isNonEnglish(slice.map { ordered[$0].surface }.joined(separator: " "))
        }
        for (windowStart, slice) in windows.enumerated() where qualifies[windowStart] {
            let backed = (windowStart > 0 && qualifies[windowStart - 1])
                || (windowStart + 1 < qualifies.count && qualifies[windowStart + 1])
            guard backed else { continue }
            for index in slice { flags[index] = true }
        }
    }

    private static func qualifyingRuns(_ ordered: [RecordedWord], flags: [Bool]) -> [Span] {
        var spans: [Span] = []
        var runStart: Int?
        for index in ordered.indices {
            if flags[index] {
                if runStart == nil { runStart = index }
                continue
            }
            if let start = runStart, let span = qualify(ordered[start..<index]) {
                spans.append(span)
            }
            runStart = nil
        }
        if let start = runStart, let span = qualify(ordered[start...]) {
            spans.append(span)
        }
        return spans
    }

    private static func qualify(_ slice: ArraySlice<RecordedWord>) -> Span? {
        guard let first = slice.first, let last = slice.last else { return nil }
        let count = slice.filter { !$0.isFiller }.count
        let duration = last.end - first.start
        guard count >= minimumWordCount || duration >= minimumDuration - 0.001 else { return nil }
        return Span(start: first.start, end: last.end, wordCount: count)
    }

    private static func isNonEnglish(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if hasNonLatinScript(trimmed) { return true }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(trimmed)
        guard recognizer.dominantLanguage != nil else { return false }
        let english = recognizer.languageHypotheses(withMaximum: 10)[.english] ?? 0
        return english < englishMaximum
    }

    /// Arabic, Hebrew, Devanagari, CJK, Cyrillic, etc. Latin-script languages use NL.
    private static func hasNonLatinScript(_ text: String) -> Bool {
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x0400...0x04FF, // Cyrillic
                 0x0590...0x05FF, // Hebrew
                 0x0600...0x06FF, // Arabic
                 0x0900...0x097F, // Devanagari
                 0x0980...0x09FF, // Bengali
                 0x0A00...0x0A7F, // Gurmukhi
                 0x0A80...0x0AFF, // Gujarati
                 0x0B80...0x0BFF, // Tamil
                 0x0C00...0x0C7F, // Telugu
                 0x0C80...0x0CFF, // Kannada
                 0x0D00...0x0D7F, // Malayalam
                 0x0E00...0x0E7F, // Thai
                 0x3040...0x30FF, // Hiragana / Katakana
                 0x3400...0x9FFF, // CJK
                 0xAC00...0xD7AF: // Hangul
                return true
            default:
                continue
            }
        }
        return false
    }
}
