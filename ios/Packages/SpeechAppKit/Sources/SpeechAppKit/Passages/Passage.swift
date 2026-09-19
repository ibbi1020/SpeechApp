import Foundation

/// One script word in a passage, with stable id for UI marking.
public struct ScriptWord: Equatable, Sendable, Codable, Identifiable {
    public let id: String
    public let surface: String
    public let syllableCount: Int
    /// High-functional-load phone tags this word contributes to struggle scheduling.
    public let phoneTags: [String]
    /// Authoritative phone sequence for specialized sound scoring (Slice B). Empty → lexicon.
    public let canonicalPhones: [String]
    public let flBand: FunctionalLoadBand

    public init(
        id: String,
        surface: String,
        syllableCount: Int = 1,
        phoneTags: [String] = [],
        canonicalPhones: [String] = [],
        flBand: FunctionalLoadBand = .medium
    ) {
        self.id = id
        self.surface = surface
        self.syllableCount = max(1, syllableCount)
        self.phoneTags = phoneTags
        self.canonicalPhones = canonicalPhones
        self.flBand = flBand
    }

    public var normalized: String {
        Self.normalize(surface)
    }

    public static func normalize(_ text: String) -> String {
        text
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .filter { $0.isLetter || $0.isNumber || $0 == "'" }
    }
}

public enum FunctionalLoadBand: String, Codable, Sendable, Comparable {
    case low
    case medium
    case high

    public static func < (lhs: FunctionalLoadBand, rhs: FunctionalLoadBand) -> Bool {
        lhs.rank < rhs.rank
    }

    private var rank: Int {
        switch self {
        case .low: return 0
        case .medium: return 1
        case .high: return 2
        }
    }
}

public struct Passage: Equatable, Sendable, Codable, Identifiable {
    public let id: String
    public let title: String
    public let words: [ScriptWord]
    /// Contrast tags covered by this passage (for NextPassagePicker).
    public let contrastTags: [String]
    public let isBalancedDefault: Bool
    /// Shared practice theme (e.g. ship-sheep) across short/medium/long variants.
    public let family: String
    public let length: PassageLength
    /// Sentence / clause place-markers for live UI (derived from `words`).
    public let spans: [PassageSpan]

    public init(
        id: String,
        title: String,
        words: [ScriptWord],
        contrastTags: [String] = [],
        isBalancedDefault: Bool = false,
        family: String? = nil,
        length: PassageLength = .short,
        spans: [PassageSpan]? = nil
    ) {
        self.id = id
        self.title = title
        self.words = words
        self.contrastTags = contrastTags
        self.isBalancedDefault = isBalancedDefault
        self.family = family ?? id
        self.length = length
        self.spans = spans ?? PassageSpanSplitter.split(words: words, passageID: id)
    }

    public var text: String {
        words.map(\.surface).joined(separator: " ")
    }

    public var totalSyllables: Int {
        words.reduce(0) { $0 + $1.syllableCount }
    }

    /// Rough calm read-aloud duration at ~150 syllables/min.
    public var estimatedSeconds: Int {
        max(15, Int((Double(totalSyllables) / 150.0) * 60.0))
    }

    /// Compact duration for picker and reading chrome.
    public var durationLabel: String {
        let minutes = max(1, Int((Double(estimatedSeconds) / 60.0).rounded()))
        return "~\(minutes) min"
    }

    public var wordCount: Int { words.count }

    public func spanIndex(forWordID wordID: String) -> Int? {
        spans.firstIndex { $0.contains(wordID: wordID) }
    }

    public func span(at index: Int) -> PassageSpan? {
        guard spans.indices.contains(index) else { return nil }
        return spans[index]
    }
}
