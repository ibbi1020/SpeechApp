import Foundation

/// Listen-back markers for Reading: passage words that were skipped or swapped.
///
/// The live aligner is generous on purpose (it fills dropped ASR words as heard so the
/// caret never jumps). Feedback needs the opposite, so this runs a strict global
/// alignment of the passage against Grok's final timed words after Stop.
public enum ReadingMarkers {
    public enum Step: Equatable, Sendable {
        case match(script: Int, spoken: Int)
        case swap(script: Int, spoken: Int)
        case skip(script: Int)
        case extra(spoken: Int)
    }

    /// Edit-distance alignment. Fillers are dropped first. Only clipped endings and
    /// spelling variants count as a match; a different sound ("fin" for "thin",
    /// "sheep" for "ship") is a swap.
    public static func align(script: [ScriptWord], spoken: [RecordedWord]) -> [Step] {
        let heard = spoken.enumerated().filter { !$0.element.isFiller }
        let s = script.map(\.normalized)
        let w = heard.map { ScriptWord.normalize($0.element.surface) }
        let rows = s.count + 1
        let cols = w.count + 1
        var cost = [[Int]](repeating: [Int](repeating: 0, count: cols), count: rows)
        for i in 0..<rows { cost[i][0] = i }
        for j in 0..<cols { cost[0][j] = j }
        if rows > 1, cols > 1 {
            for i in 1..<rows {
                for j in 1..<cols {
                    let same = same(s[i - 1], w[j - 1])
                    cost[i][j] = min(
                        cost[i - 1][j - 1] + (same ? 0 : 1),
                        cost[i - 1][j] + 1,
                        cost[i][j - 1] + 1
                    )
                }
            }
        }

        var steps: [Step] = []
        var i = s.count
        var j = w.count
        while i > 0 || j > 0 {
            if i > 0, j > 0 {
                let same = same(s[i - 1], w[j - 1])
                if cost[i][j] == cost[i - 1][j - 1] + (same ? 0 : 1) {
                    let spokenIndex = heard[j - 1].offset
                    steps.append(same ? .match(script: i - 1, spoken: spokenIndex) : .swap(script: i - 1, spoken: spokenIndex))
                    i -= 1
                    j -= 1
                    continue
                }
            }
            if i > 0, cost[i][j] == cost[i - 1][j] + 1 {
                steps.append(.skip(script: i - 1))
                i -= 1
            } else {
                steps.append(.extra(spoken: heard[j - 1].offset))
                j -= 1
            }
        }
        return steps.reversed()
    }

    /// Stricter than the live aligner's soft match, which is tuned to keep the caret
    /// moving and would hide most one-sound swaps.
    static func same(_ script: String, _ spoken: String) -> Bool {
        if script == spoken { return true }
        guard !script.isEmpty, !spoken.isEmpty else { return false }
        if TokenAligner.isFunctionWord(script) || TokenAligner.isFunctionWord(spoken) { return false }
        let shorter = min(script.count, spoken.count)
        let longer = max(script.count, spoken.count)
        // Clipped ending: "sail" for "sailed". ASR clips these often.
        if shorter >= 4, script.hasPrefix(spoken) || spoken.hasPrefix(script), longer - shorter <= 2 {
            return true
        }
        // Spelling variant of a long word: "favorite" for "favourite".
        return longer >= 6 && TokenAligner.levenshtein(script, spoken) <= 1
    }

    /// Every skipped or swapped stretch, before the cap.
    public static func candidates(passage: Passage, words: [RecordedWord]) -> [ReviewMarker] {
        let steps = align(script: passage.words, spoken: words)
        // Words after the last one heard were never reached (stopped early); the report
        // already shows how much was read, so they are not listen-back moments.
        let lastHeard = steps.lastIndex { step in
            if case .match = step { return true }
            if case .swap = step { return true }
            return false
        } ?? -1

        var markers: [ReviewMarker] = []
        var index = 0
        while index <= lastHeard {
            switch steps[index] {
            case .skip:
                var run: [Int] = []
                while index <= lastHeard, case .skip(let s) = steps[index] {
                    run.append(s)
                    index += 1
                }
                // Grok often drops "the"/"a"; a run of only function words is noise.
                if run.allSatisfy({ TokenAligner.isFunctionWord(passage.words[$0].normalized) }) {
                    continue
                }
                let before = spokenTime(steps, before: index - run.count, words: words)
                let after = spokenTime(steps, from: index, words: words)
                let start = before ?? max(0, (after ?? 0.5) - 0.5)
                let end = max(start + 0.3, after ?? start + 0.5)
                let surfaces = run.map { passage.words[$0].surface }
                markers.append(ReviewMarker(
                    kind: .skippedWord,
                    start: start,
                    end: end,
                    score: skipScore(run.map { passage.words[$0] }),
                    note: skipNote(surfaces)
                ))
            case .swap:
                var scriptRun: [Int] = []
                var spokenRun: [Int] = []
                while index <= lastHeard, case .swap(let s, let w) = steps[index] {
                    scriptRun.append(s)
                    spokenRun.append(w)
                    index += 1
                }
                let first = words[spokenRun.first!]
                let last = words[spokenRun.last!]
                markers.append(ReviewMarker(
                    kind: .swappedWord,
                    start: first.start,
                    end: max(last.end, first.start + 0.3),
                    score: swapScore(scriptRun.map { passage.words[$0] }),
                    note: swapNote(scriptRun.map { passage.words[$0].surface })
                ))
            default:
                index += 1
            }
        }
        return markers
    }

    public static func build(passage: Passage, words: [RecordedWord], durationSeconds: TimeInterval) -> [ReviewMarker] {
        ReviewMarkers.select(candidates(passage: passage, words: words), durationSeconds: durationSeconds)
    }

    // MARK: - Ranking

    /// Swaps rank by functional load: one high-load contrast hurts understanding more
    /// than several low-load ones (Munro & Derwing 2006).
    static func swapScore(_ words: [ScriptWord]) -> TimeInterval {
        words.map { word in
            switch word.flBand {
            case .high: 3
            case .medium: 2
            case .low: 1
            }
        }.max() ?? 1
    }

    /// A skipped content word costs meaning; a dropped "the" rarely does.
    static func skipScore(_ words: [ScriptWord]) -> TimeInterval {
        let total = words.reduce(0.0) { sum, word in
            sum + (TokenAligner.isFunctionWord(word.normalized) ? 0.5 : 1.5)
        }
        return min(3, total)
    }

    // MARK: - Wording (ask, never correct)

    static func swapNote(_ surfaces: [String]) -> String {
        "The passage says “\(quote(surfaces))”. Listen: what did you say?"
    }

    static func skipNote(_ surfaces: [String]) -> String {
        "We didn't hear “\(quote(surfaces))”. Listen: did you read it?"
    }

    private static func quote(_ surfaces: [String]) -> String {
        surfaces
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .joined(separator: " ")
    }

    // MARK: - Times

    private static func spokenTime(_ steps: [Step], before index: Int, words: [RecordedWord]) -> TimeInterval? {
        var i = index - 1
        while i >= 0 {
            switch steps[i] {
            case .match(_, let w), .swap(_, let w), .extra(let w): return words[w].end
            case .skip: i -= 1
            }
        }
        return nil
    }

    private static func spokenTime(_ steps: [Step], from index: Int, words: [RecordedWord]) -> TimeInterval? {
        var i = index
        while i < steps.count {
            switch steps[i] {
            case .match(_, let w), .swap(_, let w), .extra(let w): return words[w].start
            case .skip: i += 1
            }
        }
        return nil
    }
}

extension Passage {
    /// A throwaway passage from plain text, for tests and the eval CLI.
    public static func plain(_ text: String, id: String = "eval", flBand: FunctionalLoadBand = .medium) -> Passage {
        let words = text.split(whereSeparator: \.isWhitespace).enumerated().map { index, surface in
            ScriptWord(id: "\(id)-\(index)", surface: String(surface), flBand: flBand)
        }
        return Passage(id: id, title: id, words: words)
    }
}
