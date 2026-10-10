import Foundation

/// A tiny script format for feedback test cases. It says what is spoken and
/// what the feedback system should notice, in one line:
///
///     So [2.0 pause] I went <fillers> um to the uh </> store
///
/// - `[2.5]` is 2.5 s of silence. Add `pause`, `pause maybe`, or `not pause` to label it.
/// - `<fillers> … </>` and `<restart> … </>` wrap words that should be flagged.
///   `<restart maybe>` means the cap may hide it; `<not restart>` means it must not be flagged.
/// - Anything else is a spoken word.
public struct FeedbackScript: Equatable, Sendable {
    public enum Item: Equatable, Sendable {
        case word(String)
        case silence(TimeInterval, Label?)
        case open(Label)
        case close
    }

    public struct Label: Equatable, Sendable {
        public let kind: ReviewMarker.Kind
        public let expect: FeedbackLabel.Expectation
    }

    /// A stretch of words with no silence or label edge inside, said in one go.
    public enum Segment: Equatable, Sendable {
        case speech([String])
        case silence(TimeInterval)
    }

    public struct Layout: Equatable, Sendable {
        public let words: [RecordedWord]
        public let labels: [FeedbackLabel]
        public let duration: TimeInterval
    }

    public enum ParseError: Error, Equatable {
        case badSilence(String)
        case badTag(String)
        case unclosedTag
        case strayClose
    }

    public let items: [Item]

    public init(_ text: String) throws {
        var items: [Item] = []
        var depth = 0
        for token in Self.tokens(text) {
            if token.hasPrefix("[") {
                let inner = token.dropFirst().dropLast().split(separator: " ").map(String.init)
                guard let first = inner.first, let seconds = TimeInterval(first), seconds >= 0 else {
                    throw ParseError.badSilence(token)
                }
                let label = inner.count > 1 ? try Self.label(Array(inner.dropFirst()), token: token) : nil
                items.append(.silence(seconds, label))
            } else if token.hasPrefix("</") {
                guard depth > 0 else { throw ParseError.strayClose }
                depth -= 1
                items.append(.close)
            } else if token.hasPrefix("<") {
                let inner = token.dropFirst().dropLast().split(separator: " ").map(String.init)
                items.append(.open(try Self.label(inner, token: token)))
                depth += 1
            } else {
                items.append(.word(token))
            }
        }
        guard depth == 0 else { throw ParseError.unclosedTag }
        self.items = items
    }

    /// Words, silences, and label edges split into the chunks a voice would say in one go.
    public var segments: [Segment] {
        var out: [Segment] = []
        var run: [String] = []
        func flush() {
            if !run.isEmpty { out.append(.speech(run)) }
            run = []
        }
        for item in items {
            switch item {
            case .word(let word): run.append(word)
            case .silence(let seconds, _):
                flush()
                out.append(.silence(seconds))
            case .open, .close: flush()
            }
        }
        flush()
        return out
    }

    /// Fixed word timing for rule tests: each word 0.3 s, 0.1 s between words.
    public func layout(wordDuration: TimeInterval = 0.3, wordGap: TimeInterval = 0.1) -> Layout {
        layout(gapBetweenSpeech: wordGap) { words in
            let times = words.indices.map { index -> (TimeInterval, TimeInterval) in
                let start = Double(index) * (wordDuration + wordGap)
                return (start, start + wordDuration)
            }
            let length = Double(words.count) * (wordDuration + wordGap) - wordGap
            return (times, length)
        }
    }

    /// Lay the script out using measured speech lengths (for generated audio).
    /// `measure` returns each word's start/end inside its segment and the segment length.
    public func layout(
        gapBetweenSpeech: TimeInterval,
        measure: ([String]) -> (words: [(TimeInterval, TimeInterval)], length: TimeInterval)
    ) -> Layout {
        var words: [RecordedWord] = []
        var labels: [FeedbackLabel] = []
        var openSpans: [(label: Label, firstWord: Int)] = []
        var clock: TimeInterval = 0
        var lastWasSpeech = false
        var pending: [String] = []

        func flushSpeech() {
            guard !pending.isEmpty else { return }
            if lastWasSpeech { clock += gapBetweenSpeech }
            let measured = measure(pending)
            for (index, surface) in pending.enumerated() {
                let time = index < measured.words.count ? measured.words[index] : (0, measured.length)
                words.append(RecordedWord(surface: surface, start: clock + time.0, end: clock + time.1))
            }
            clock += measured.length
            pending = []
            lastWasSpeech = true
        }

        for item in items {
            switch item {
            case .word(let word):
                pending.append(word)
            case .silence(let seconds, let label):
                flushSpeech()
                let start = clock
                clock += seconds
                lastWasSpeech = false
                if let label {
                    labels.append(FeedbackLabel(kind: label.kind, start: start, end: clock, expect: label.expect))
                }
            case .open(let label):
                flushSpeech()
                openSpans.append((label, words.count))
            case .close:
                flushSpeech()
                guard let span = openSpans.popLast() else { continue }
                let inside = words[span.firstWord...]
                if let first = inside.first, let last = inside.last {
                    labels.append(
                        FeedbackLabel(kind: span.label.kind, start: first.start, end: last.end, expect: span.label.expect)
                    )
                }
            }
        }
        flushSpeech()
        return Layout(words: words, labels: labels.sorted { $0.start < $1.start }, duration: clock)
    }

    private static func tokens(_ text: String) -> [String] {
        var out: [String] = []
        var index = text.startIndex
        while index < text.endIndex {
            let char = text[index]
            if char.isWhitespace {
                index = text.index(after: index)
                continue
            }
            if char == "[" || char == "<" {
                let closer: Character = char == "[" ? "]" : ">"
                let end = text[index...].firstIndex(of: closer) ?? text.index(before: text.endIndex)
                out.append(String(text[index...end]))
                index = text.index(after: end)
                continue
            }
            var end = index
            while end < text.endIndex, !text[end].isWhitespace, text[end] != "[", text[end] != "<" {
                end = text.index(after: end)
            }
            out.append(String(text[index..<end]))
            index = end
        }
        return out
    }

    private static func label(_ words: [String], token: String) throws -> Label {
        var parts = words.map { $0.lowercased() }
        var expect = FeedbackLabel.Expectation.marker
        if parts.first == "not" {
            expect = .none
            parts.removeFirst()
        }
        if parts.last == "maybe" {
            expect = .candidate
            parts.removeLast()
        }
        guard parts.count == 1, let kind = FeedbackLabel.kindFromWord(parts[0]) else {
            throw ParseError.badTag(token)
        }
        return Label(kind: kind, expect: expect)
    }
}
