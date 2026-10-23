import Foundation

/// Where a pause falls in the sentence, judged from the words on each side.
///
/// Grok punctuation alone is not enough: it often writes a period at a long pause
/// ("I work at a small. Bakery"). So a pause only counts as between sentences when a
/// sentence-ending mark is followed by a word that starts a new clause.
enum PauseSpot: Equatable, Sendable {
    case midClause
    case betweenClauses
    case unknown

    /// Words that cannot end a clause: the sentence must go on after them.
    static let cannotEnd: Set<String> = [
        "a", "an", "the", "my", "your", "his", "her", "our", "their", "its", "this", "these", "those",
        "of", "to", "in", "on", "at", "for", "with", "from", "by", "about", "into", "onto", "over",
        "under", "between", "through", "during", "without", "and", "but", "or", "because", "if",
        "when", "while", "although", "than", "very", "really", "quite", "i", "we", "they", "he", "she",
    ]

    /// Words that commonly start a new clause or sentence.
    static let clauseStarters: Set<String> = [
        "i", "we", "you", "he", "she", "they", "it", "there", "this", "that", "so", "and", "but",
        "then", "also", "well", "now", "because", "when", "after", "before", "if", "the", "my",
        "our", "usually", "sometimes", "actually", "anyway", "first", "next", "finally", "maybe",
    ]

    static func classify(before: RecordedWord, after: RecordedWord) -> PauseSpot {
        let previous = ScriptWord.normalize(before.surface)
        if cannotEnd.contains(previous) { return .midClause }
        let endsSentence = before.surface.last.map { ".?!;:".contains($0) } ?? false
        let next = ScriptWord.normalize(after.surface)
        if endsSentence, clauseStarters.contains(next) { return .betweenClauses }
        return .unknown
    }
}
