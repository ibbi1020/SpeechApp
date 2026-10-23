import Foundation

/// Streaming alignment operators (locked architecture list).
public enum AlignmentOperator: String, Equatable, Sendable, Codable {
    case match
    case substitute
    case skipScript = "skip-script"
    case insertSpoken = "insert-spoken"
    case `repeat`
    case restart
    case unmatched
}

public struct SpokenToken: Equatable, Sendable {
    public let surface: String
    public let startTime: TimeInterval?
    public let endTime: TimeInterval?
    public let isFinal: Bool

    public init(
        surface: String,
        startTime: TimeInterval? = nil,
        endTime: TimeInterval? = nil,
        isFinal: Bool = true
    ) {
        self.surface = surface
        self.startTime = startTime
        self.endTime = endTime
        self.isFinal = isFinal
    }

    public var normalized: String {
        ScriptWord.normalize(surface)
    }
}

public struct AlignmentEvent: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let op: AlignmentOperator
    public let scriptWordID: String?
    public let scriptSurface: String?
    public let spokenSurface: String?
    public let scriptIndex: Int?

    public init(
        id: UUID = UUID(),
        op: AlignmentOperator,
        scriptWordID: String? = nil,
        scriptSurface: String? = nil,
        spokenSurface: String? = nil,
        scriptIndex: Int? = nil
    ) {
        self.id = id
        self.op = op
        self.scriptWordID = scriptWordID
        self.scriptSurface = scriptSurface
        self.spokenSurface = spokenSurface
        self.scriptIndex = scriptIndex
    }
}

public struct LiveMark: Equatable, Sendable, Identifiable {
    public enum Kind: String, Equatable, Sendable {
        case skip
        case extra
        case substitute
        case poorSound
        case notAssessed
    }

    public let id: UUID
    public let kind: Kind
    public let scriptWordID: String?
    public let spokenSurface: String?
    public let message: String

    public init(
        id: UUID = UUID(),
        kind: Kind,
        scriptWordID: String? = nil,
        spokenSurface: String? = nil,
        message: String = ""
    ) {
        self.id = id
        self.kind = kind
        self.scriptWordID = scriptWordID
        self.spokenSurface = spokenSurface
        self.message = message
    }
}

/// Non-mutating live preview from volatile / partial ASR hypotheses.
public struct VolatilePreview: Equatable, Sendable {
    public let currentWordID: String?
    /// Script words soft/exact-matched by the volatile hypothesis beyond the committed cursor.
    public let provisionalMatchedIDs: [String]
    /// Intermediates jumped when a later script word matched (keep-going recovery).
    public let provisionalSkippedIDs: [String]

    public init(
        currentWordID: String?,
        provisionalMatchedIDs: [String] = [],
        provisionalSkippedIDs: [String] = []
    ) {
        self.currentWordID = currentWordID
        self.provisionalMatchedIDs = provisionalMatchedIDs
        self.provisionalSkippedIDs = provisionalSkippedIDs
    }
}

/// Streaming, bounded-lookahead aligner against a known script.
///
/// Finalized tokens commit marks. Volatile tokens only move a provisional cursor
/// (Monkeytype-like responsiveness) without painting skips/substitutes early.
public final class TokenAligner: @unchecked Sendable {
    public struct Configuration: Equatable, Sendable {
        /// Prefer near-miss ASR hypotheses as occupancy matches against the known script.
        /// This is follow-along tolerance, not a pronunciation pass.
        public var softScriptMatch: Bool

        public init(softScriptMatch: Bool = true) {
            self.softScriptMatch = softScriptMatch
        }
    }

    public let script: [ScriptWord]
    public let lookahead: Int
    public let configuration: Configuration

    private(set) public var scriptCursor: Int = 0
    private(set) public var events: [AlignmentEvent] = []
    private(set) public var currentWordID: String?
    /// Highest script index the live caret has reached (never moves backward).
    private var farthestCaretIndex: Int = 0

    public init(
        script: [ScriptWord],
        lookahead: Int = 4,
        configuration: Configuration = .init()
    ) {
        self.script = script
        self.lookahead = max(1, lookahead)
        self.configuration = configuration
        self.currentWordID = script.first?.id
        self.farthestCaretIndex = 0
    }

    public convenience init(
        passage: Passage,
        lookahead: Int = 4,
        configuration: Configuration = .init()
    ) {
        self.init(script: passage.words, lookahead: lookahead, configuration: configuration)
    }

    /// Ingest one finalized spoken token and emit zero or more alignment events.
    @discardableResult
    public func ingest(_ spoken: SpokenToken) -> [AlignmentEvent] {
        guard spoken.isFinal else { return [] }
        let spokenNorm = spoken.normalized
        guard !spokenNorm.isEmpty else { return [] }

        if scriptCursor >= script.count {
            let event = AlignmentEvent(
                op: .insertSpoken,
                spokenSurface: spoken.surface
            )
            events.append(event)
            return [event]
        }

        // Exact or soft match at cursor (soft = accent-tolerant occupancy only)
        if matches(script[scriptCursor].normalized, spokenNorm) {
            return emitMatch(spoken: spoken)
        }

        // Look ahead for the spoken word in upcoming script.
        // Intermediates are occupancy fill, not user-skips: Apple finals routinely
        // drop short/mid words, and unique-content leap then false-skips them.
        if let ahead = findAhead(spokenNorm) {
            var produced: [AlignmentEvent] = []
            while scriptCursor < ahead {
                produced.append(contentsOf: emitScriptMatch())
            }
            produced.append(contentsOf: emitMatch(spoken: spoken))
            return produced
        }

        // Repeat of previous matched word
        if scriptCursor > 0, matches(script[scriptCursor - 1].normalized, spokenNorm) {
            let prev = script[scriptCursor - 1]
            let event = AlignmentEvent(
                op: .repeat,
                scriptWordID: prev.id,
                scriptSurface: prev.surface,
                spokenSurface: spoken.surface,
                scriptIndex: scriptCursor - 1
            )
            events.append(event)
            return [event]
        }

        // Restart: only when the spoken token is the first script word *and* not a
        // function word. Short late finals like "the quick" were rewinding occupancy.
        if scriptCursor > 1,
           script[0].normalized == spokenNorm,
           !Self.isFunctionWord(spokenNorm) {
            let event = AlignmentEvent(
                op: .restart,
                scriptWordID: script[0].id,
                scriptSurface: script[0].surface,
                spokenSurface: spoken.surface,
                scriptIndex: 0
            )
            events.append(event)
            scriptCursor = 0
            return emitMatch(spoken: spoken)
        }

        // Unknown spoken word: treat as extra. Do NOT steal the current script word
        // (hold-not-substitute) — advancing here desyncs the karaoke caret.
        let event = AlignmentEvent(
            op: .insertSpoken,
            spokenSurface: spoken.surface
        )
        events.append(event)
        return [event]
    }

    /// Script word IDs that were skip-scripted (missed while reading ahead).
    public var skippedWordIDs: [String] {
        events.compactMap { event in
            guard event.op == .skipScript else { return nil }
            return event.scriptWordID
        }
    }

    /// Never move the live caret backward. If `proposing` is behind the farthest
    /// reached word, keep the farthest; otherwise advance.
    public func monotonicWordID(proposing: String?) -> String? {
        guard let proposing else {
            return farthestCaretIndex < script.count ? script[farthestCaretIndex].id : nil
        }
        guard let proposedIndex = script.firstIndex(where: { $0.id == proposing }) else {
            return currentWordID
        }
        if proposedIndex < farthestCaretIndex {
            return farthestCaretIndex < script.count ? script[farthestCaretIndex].id : nil
        }
        farthestCaretIndex = proposedIndex
        return proposing
    }

    /// Among ASR alternatives, pick the surface list that best occupies the
    /// upcoming script window (exact/soft matches from the committed cursor).
    public func bestScriptAlternative(candidates: [[String]]) -> [String]? {
        var best: [String]?
        var bestRank = (score: Int.min, length: Int.min)
        for candidate in candidates {
            let rank = (score: occupancyScore(surfaces: candidate), length: candidate.count)
            if rank > bestRank {
                bestRank = rank
                best = candidate
            }
        }
        return best
    }

    private func occupancyScore(surfaces: [String]) -> Int {
        var cursor = scriptCursor
        var score = 0
        for spokenNorm in stripCommittedPrefix(from: surfaces) {
            guard cursor < script.count else { break }
            if matches(script[cursor].normalized, spokenNorm) {
                score += 2
                cursor += 1
                continue
            }
            if let ahead = findUniqueContentAhead(spokenNorm, from: cursor + 1) {
                score += 1
                cursor = ahead + 1
                continue
            }
            break
        }
        return score
    }

    /// Preview volatile ASR text without mutating committed alignment.
    ///
    /// Advances on exact/soft matches at the cursor. Unique-content jump-ahead
    /// fills omitted words as heard. Function-word leftovers are skipped, not a freeze.
    public func previewVolatile(surfaces: [String]) -> VolatilePreview {
        var cursor = scriptCursor
        var provisionalMatched: [String] = []

        for spokenNorm in stripCommittedPrefix(from: surfaces) {
            guard cursor < script.count else { break }
            let matchedThrough: Int
            if matches(script[cursor].normalized, spokenNorm) {
                matchedThrough = cursor
            } else if let ahead = findUniqueContentAhead(spokenNorm, from: cursor + 1) {
                matchedThrough = ahead
            } else if Self.isFunctionWord(spokenNorm) {
                continue
            } else {
                break
            }
            provisionalMatched.append(contentsOf: script[cursor...matchedThrough].map(\.id))
            cursor = matchedThrough + 1
        }

        return VolatilePreview(
            currentWordID: cursor < script.count ? script[cursor].id : nil,
            provisionalMatchedIDs: provisionalMatched
        )
    }

    /// Drop surfaces already accounted for by the committed script cursor when the
    /// hypothesis is cumulative (common for progressive Dictation/Speech results).
    ///
    /// Exact walk first. If the last committed word was substituted or dropped,
    /// treat the prefix as done and keep the remainder so occupancy can continue.
    private func stripCommittedPrefix(from surfaces: [String]) -> [String] {
        let spoken = surfaces.map(ScriptWord.normalize).filter { !$0.isEmpty }
        guard scriptCursor > 0, !spoken.isEmpty else { return spoken }

        var spokenIdx = 0
        var scriptIdx = 0
        var extras = 0
        let extraBudget = 4
        while scriptIdx < scriptCursor, spokenIdx < spoken.count {
            if script[scriptIdx].normalized == spoken[spokenIdx] {
                scriptIdx += 1
                spokenIdx += 1
                continue
            }
            // Last committed word was substituted — keep that spoken token and the tail.
            if scriptIdx == scriptCursor - 1 {
                return Array(spoken.dropFirst(spokenIdx))
            }
            extras += 1
            if extras > extraBudget { break }
            spokenIdx += 1
        }
        guard scriptIdx >= scriptCursor else { return spoken }
        return Array(spoken.dropFirst(spokenIdx))
    }

    /// Promote sticky-heard script words still sitting at the cursor into matches.
    /// Used on Stop so volatile “heard” trail isn’t wiped by `finish()` skips.
    @discardableResult
    public func commitHeardTrail(_ heardIDs: Set<String>) -> [AlignmentEvent] {
        var ids: [String] = []
        var index = scriptCursor
        while index < script.count, heardIDs.contains(script[index].id) {
            ids.append(script[index].id)
            index += 1
        }
        return commitProvisionalMatches(ids)
    }

    /// Promote a volatile occupancy preview into committed match events (e.g. on Stop).
    /// IDs already behind the cursor are skipped so a stale prefix does not abort the tail.
    @discardableResult
    public func commitProvisionalMatches(_ wordIDs: [String]) -> [AlignmentEvent] {
        var produced: [AlignmentEvent] = []
        for id in wordIDs {
            guard scriptCursor < script.count else { break }
            guard script[scriptCursor].id == id else { continue }
            produced.append(contentsOf: emitScriptMatch())
        }
        return produced
    }

    /// Mark remaining unread script words as skips (e.g. on Stop).
    @discardableResult
    public func finish() -> [AlignmentEvent] {
        var produced: [AlignmentEvent] = []
        while scriptCursor < script.count {
            let skipped = script[scriptCursor]
            let event = AlignmentEvent(
                op: .skipScript,
                scriptWordID: skipped.id,
                scriptSurface: skipped.surface,
                scriptIndex: scriptCursor
            )
            events.append(event)
            produced.append(event)
            scriptCursor += 1
        }
        currentWordID = nil
        return produced
    }

    public func liveMarks(from events: [AlignmentEvent]? = nil) -> [LiveMark] {
        let source = events ?? self.events
        return source.compactMap { event in
            switch event.op {
            case .skipScript:
                return LiveMark(
                    kind: .skip,
                    scriptWordID: event.scriptWordID,
                    message: "Skipped"
                )
            case .insertSpoken:
                return LiveMark(
                    kind: .extra,
                    spokenSurface: event.spokenSurface,
                    message: "+\(event.spokenSurface ?? "")"
                )
            case .substitute:
                return LiveMark(
                    kind: .substitute,
                    scriptWordID: event.scriptWordID,
                    spokenSurface: event.spokenSurface,
                    message: "Said \(event.spokenSurface ?? "?")"
                )
            default:
                return nil
            }
        }
    }

    /// Accent-tolerant occupancy at the **current** word only.
    /// Soft enough for Apple near-misses; not so loose it steals later script words.
    public static func isSoftMatch(_ scriptNorm: String, _ spokenNorm: String) -> Bool {
        if scriptNorm == spokenNorm { return true }
        guard !scriptNorm.isEmpty, !spokenNorm.isEmpty else { return false }

        // Never soft-collapse minimal pairs used as contrast drills (ship≠sheep, …).
        if blockedMinimalPairs.contains([scriptNorm, spokenNorm]) {
            return false
        }

        // Function words: exact only — soft "a"/"an"/"to" caused false locks.
        if isFunctionWord(scriptNorm) || isFunctionWord(spokenNorm) {
            return false
        }

        let shorter = min(scriptNorm.count, spokenNorm.count)
        let longer = max(scriptNorm.count, spokenNorm.count)
        // Stem / truncation: ASR often clips endings on content words.
        if shorter >= 4,
           scriptNorm.hasPrefix(spokenNorm) || spokenNorm.hasPrefix(scriptNorm),
           longer - shorter <= 2 {
            return true
        }

        let maxLen = longer
        let threshold: Int
        switch maxLen {
        case 0...4:
            threshold = 1
        case 5...8:
            threshold = 2
        default:
            threshold = 3
        }
        return levenshtein(scriptNorm, spokenNorm) <= threshold
    }

    private static let blockedMinimalPairs: Set<Set<String>> = [
        ["ship", "sheep"],
        ["sit", "seat"],
        ["bit", "beat"],
        ["live", "leave"],
    ]

    private func matches(_ scriptNorm: String, _ spokenNorm: String) -> Bool {
        if scriptNorm == spokenNorm { return true }
        guard configuration.softScriptMatch else { return false }
        return Self.isSoftMatch(scriptNorm, spokenNorm)
    }

    private func emitMatch(spoken: SpokenToken) -> [AlignmentEvent] {
        let word = script[scriptCursor]
        let event = AlignmentEvent(
            op: .match,
            scriptWordID: word.id,
            scriptSurface: word.surface,
            spokenSurface: spoken.surface,
            scriptIndex: scriptCursor
        )
        events.append(event)
        scriptCursor += 1
        updateCurrentWordID()
        return [event]
    }

    /// Occupancy fill for a script word with no corresponding ASR token.
    private func emitScriptMatch() -> [AlignmentEvent] {
        emitMatch(spoken: SpokenToken(surface: script[scriptCursor].surface, isFinal: true))
    }

    private func updateCurrentWordID() {
        if scriptCursor < script.count {
            currentWordID = script[scriptCursor].id
            farthestCaretIndex = max(farthestCaretIndex, scriptCursor)
        } else {
            currentWordID = nil
            farthestCaretIndex = max(farthestCaretIndex, script.count)
        }
    }

    /// Look ahead for catch-up: exact match, unique in the window, and not a
    /// function word. Common ASR tokens like "the"/"to" must never leap the caret.
    private func findAhead(_ spokenNorm: String) -> Int? {
        findUniqueContentAhead(spokenNorm, from: scriptCursor + 1)
    }

    private func findInRange(_ spokenNorm: String, from: Int, to: Int) -> Int? {
        guard from < to else { return nil }
        for i in from..<to {
            if matches(script[i].normalized, spokenNorm) {
                return i
            }
        }
        return nil
    }

    /// Exact + unique + content-word only. Soft match is for the *current* word, not jumps.
    private func findUniqueContentAhead(_ spokenNorm: String, from: Int) -> Int? {
        guard !spokenNorm.isEmpty, !Self.isFunctionWord(spokenNorm) else { return nil }
        let end = min(from + lookahead, script.count)
        guard from < end else { return nil }

        var hits: [Int] = []
        for i in from..<end {
            // Exact only — soft-matching ahead caused false skips (near-miss to a later word).
            if script[i].normalized == spokenNorm {
                hits.append(i)
            }
        }
        guard hits.count == 1 else { return nil }
        return hits[0]
    }

    private static let functionWords: Set<String> = [
        "a", "an", "the", "to", "of", "and", "in", "on", "is", "it", "for", "as", "at",
        "be", "by", "or", "if", "we", "you", "he", "she", "they", "i", "me", "my", "our",
        "your", "his", "her", "its", "their", "this", "that", "these", "those", "with",
        "from", "was", "are", "were", "been", "am", "do", "does", "did", "not", "no",
        "but", "so", "than", "then", "there", "here", "what", "when", "who", "how",
        "can", "could", "would", "should", "will", "just", "about", "into", "out", "up",
    ]

    static func isFunctionWord(_ normalized: String) -> Bool {
        functionWords.contains(normalized)
    }

    static func levenshtein(_ a: String, _ b: String) -> Int {
        let aChars = Array(a)
        let bChars = Array(b)
        if aChars.isEmpty { return bChars.count }
        if bChars.isEmpty { return aChars.count }
        var prev = Array(0...bChars.count)
        var cur = Array(repeating: 0, count: bChars.count + 1)
        for i in 1...aChars.count {
            cur[0] = i
            for j in 1...bChars.count {
                let cost = aChars[i - 1] == bChars[j - 1] ? 0 : 1
                cur[j] = min(
                    prev[j] + 1,
                    cur[j - 1] + 1,
                    prev[j - 1] + cost
                )
            }
            swap(&prev, &cur)
        }
        return prev[bChars.count]
    }
}
